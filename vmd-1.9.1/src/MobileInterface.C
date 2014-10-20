/***************************************************************************
 *cr                                                                       
 *cr            (C) Copyright 1995-2011 The Board of Trustees of the           
 *cr                        University of Illinois                       
 *cr                         All Rights Reserved                        
 *cr                                                                   
 ***************************************************************************/

/***************************************************************************
 * RCS INFORMATION:
 *
 *	$RCSfile: MobileInterface.C,v $
 *	$Author: kvandivo $	$Locker:  $		$State: Exp $
 *	$Revision: 1.25 $	$Date: 2012/01/28 19:28:17 $
 *
 ***************************************************************************
 * DESCRIPTION:
 *
 * The Mobile UI object, which maintains the current state of connected
 * smartmobile/tablet clients.
 *
 ***************************************************************************
 * TODO list:
 *      Pretty much everything          
 *
 ***************************************************************************/

/* socket stuff */
#if defined(_MSC_VER)
#include <winsock2.h>
#else
#include <stdio.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/socket.h>
#include <time.h>
#include <netinet/in.h>
#endif

#include "MobileInterface.h"
#include "DisplayDevice.h"
#include "TextEvent.h"
#include "CommandQueue.h"
#include "Inform.h"
#include "PickList.h"
#include "Animation.h"
#include "VMDApp.h"
#include "math.h"
#include "stdlib.h" // for getenv(), abs() etc.

// ------------------------------------------------------------------------
/* Only works with aligned 4-byte quantities, will cause a bus error */
/* on some platforms if used on unaligned data.                      */
static void swap4_aligned(void *v, long ndata) {
  int *data = (int *) v;
  long i;
  int *N;
  for (i=0; i<ndata; i++) {
    N = data + i;
    *N=(((*N>>24)&0xff) | ((*N&0xff)<<24) |
        ((*N>>8)&0xff00) | ((*N&0xff00)<<8));
  }
}

// ------------------------------------------------------------------------

typedef struct {
  /* socket management data */
  char buffer[1024];
  struct sockaddr_in sockaddr;
#if defined(_MSC_VER)
  SOCKET sockfd;
#else
  int sockfd;
#endif
  int fromlen;

  /* mobile state vector */
  int seqnum;
  int buttons;
  float rx;
  float ry;
  float rz;
  float tx;
  float ty;
  float tz;
  int padaction;
  int touchcnt;
  int upid;
  int touchid[16];
  float padx[16];
  float pady[16];
  float rotmatrix[9];
} mobilehandle;


// ------------------------------------------------------------------------
static void * mobile_listener_create(int port) {
  mobilehandle *ph = (mobilehandle *) calloc(1, sizeof(mobilehandle));
  if (ph == NULL)
    return NULL;

#if defined(_MSC_VER)
  // ensure that winsock is initialized
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2,2), &wsaData) != NO_ERROR)
    return NULL;
#endif

  if ((ph->sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
    perror("socket: ");
    free(ph);
    return NULL;
  }

  /* make socket non-blocking */
#if defined(_MSC_VER)
  u_long nonblock = 1;
  ioctlsocket(ph->sockfd, FIONBIO, &nonblock);
#else
  int sockflags;
  sockflags = fcntl(ph->sockfd, F_GETFL, 0);
  fcntl(ph->sockfd, F_SETFL, sockflags | O_NONBLOCK);
#endif

  memset(&ph->sockaddr, 0, sizeof(ph->sockaddr));
  ph->sockaddr.sin_family      = AF_INET;
  ph->sockaddr.sin_addr.s_addr = htonl(INADDR_ANY);
  ph->sockaddr.sin_port        = htons(port);

  if (bind(ph->sockfd, (struct sockaddr *)&ph->sockaddr, sizeof(sockaddr)) < 0) {
    perror("bind: ");
    free(ph);
    return NULL;
  }

  return ph;
}

// ------------------------------------------------------------------------
// maximum API version that we understand
#define CURRENTAPIVERSION       8 


                                 // packet contains:
#define PACKET_ORIENT       1    //   device orientation (gyro, accel, etc)
#define PACKET_TOUCH        2    //   touchpad events (up, down, move, etc)
#define PACKET_HEARTBEAT    3    //   heartbeat.. likely every second
#define PACKET_CONNECT      4    //   information about new connection
#define PACKET_DISCONNECT   5    //   notice that a device has disconnected
#define PACKET_BUTTON       6    //   button state has changed.

#define EVENT_NON_TOUCH     -1
#define EVENT_TOUCH_DOWN     0
#define EVENT_TOUCH_UP       1
#define EVENT_TOUCH_MOVE     2
#define EVENT_TOUCH_SOMEUP   5
#define EVENT_TOUCH_SOMEDOWN 6

// ------------------------------------------------------------------------
static int mobile_listener_poll(void *voidhandle,
                        float &tx, float &ty, float &tz,
                        float &rx, float &ry, float &rz,
                        int &padaction, int &upid,
                        int &touchcnt, int *touchid,
                        float *padx, float *pady,
                        int &buttons, int &packtype, JString &incomingIP,
                        JString &currentNick) {
  mobilehandle *ph = (mobilehandle *) voidhandle;

  memset(ph->buffer, 0, sizeof(ph->buffer));
#if defined(_MSC_VER)
  int fromlen=sizeof(ph->sockaddr);
#else
  socklen_t fromlen=sizeof(ph->sockaddr);
#endif
  int packlen=0;

  packlen=recvfrom(ph->sockfd, ph->buffer, sizeof(ph->buffer), 0, (struct sockaddr *)&ph->sockaddr, &fromlen);
  /* no packets read */
  if (packlen < 1) {
    return 0;
  }

  /* we now have info.  Decode it */
  if (((int*)ph->buffer)[0] != 1) {
    swap4_aligned(ph->buffer, sizeof(ph->buffer) / 4);
  }
  if (((int*)ph->buffer)[0] != 1) {
    printf("Received unrecognized mobile packet...\n");
    return 0;
  }

  int endianism  = ((int*)ph->buffer)[0];     /* endianism.  Should be 1  */
  int apiversion = ((int*)ph->buffer)[1];     /* API version */

  /* drop old format packets, or packets with incorrect protocol,   */
  /* corruption, or that aren't formatted correctly for some reason */
  if (endianism != 1 || (apiversion < 7 || apiversion > CURRENTAPIVERSION)) {
    msgWarn << "Dropped incoming mobile input packet from "
            << inet_ntoa((ph->sockaddr).sin_addr)
            << ", version: " << apiversion << sendmsg;
    return 0;
  }

  // there are now 16 bytes of data for the nickname
  char nickName[17];
  memcpy(nickName, ph->buffer+8, 16);  // this might not be null terminated
  nickName[16] = 0;   // so we'll put a null in the last element of the char*
  currentNick = nickName;
//fprintf(stderr, "currentNick is %s\n", (const char *)currentNick);
  packtype   = ((int*)ph->buffer)[6];     /* payload description */
//  if (packtype == PACKET_HEARTBEAT) { fprintf(stderr,"{HB}"); }
  ph->buttons    = ((int*)ph->buffer)[7];     /* button state */
  ph->seqnum     = ((int*)ph->buffer)[8];     /* sequence number */

  buttons = ph->buttons;
  incomingIP = inet_ntoa((ph->sockaddr).sin_addr);

  padaction = EVENT_NON_TOUCH;

  // check to see if we need to go farther
  //if (packtype != PACKET_ORIENT && packtype != PACKET_TOUCH)
//  {
//    return 1;
//  }

  // clear previous state from handle before decoding incoming packet
  ph->rx = 0;
  ph->ry = 0;
  ph->rz = 0;
  ph->tx = 0;
  ph->ty = 0;
  ph->tz = 0;
  ph->padaction = EVENT_NON_TOUCH;
  ph->upid = 0;
  memset(ph->touchid, 0, sizeof(ph->touchid));
  memset(ph->padx, 0, sizeof(ph->padx));
  memset(ph->pady, 0, sizeof(ph->pady));
  memset(ph->rotmatrix, 0, sizeof(9*sizeof(float)));


  // decode incoming packet based on packet type
  int i;
  switch (packtype) {
    case PACKET_ORIENT:
      // Android sensor/orientation packet
      // r[0]: Azimuth, rotation around the Z axis (0<=azimuth<360).
      //       0 = North, 90 = East, 180 = South, 270 = West
      // r[1]: Pitch, rotation around X axis (-180<=pitch<=180),
      //       with positive values when the z-axis moves toward the y-axis.
      // r[2]: Roll, rotation around Y axis (-90<=roll<=90),
      //       with positive values when the z-axis moves toward the x-axis.
      ph->rz         = ((float*)ph->buffer)[ 9]; /* orientation 0 */
      ph->rx         = ((float*)ph->buffer)[10]; /* orientation 1 */
      ph->ry         = ((float*)ph->buffer)[11]; /* orientation 2 */
      ph->tx         = ((float*)ph->buffer)[12]; /* accel 0 */
      ph->ty         = ((float*)ph->buffer)[13]; /* accel 1 */
      ph->tz         = ((float*)ph->buffer)[14]; /* accel 2 */

      /* 3x3 rotation matrix stored as 9 floats */
      for (i=0; i<9; i++)
        ph->rotmatrix[i] = ((float*)ph->buffer)[15+i];
      break;

    case PACKET_TOUCH:  case PACKET_HEARTBEAT:
      float xdpi = ((float*)ph->buffer)[9];      /* X dots-per-inch */
      float ydpi = ((float*)ph->buffer)[10];      /* Y dots-per-inch */
//      int xsz    = ((int*)ph->buffer)[11];        /* screen size in pixels */
//      int ysz    = ((int*)ph->buffer)[12];        /* screen size in pixels */
      float xinvdpi = 1.0f / xdpi;
      float yinvdpi = 1.0f / ydpi;

      /* For single touch, Actions are basically:  0:down, 2: move, 1: up.  */
      /* for multi touch, the actions can indicate, by masking, which pointer
         is being manipulated */
      ph->padaction = ((int*) ph->buffer)[13];   /* action */
      ph->upid      = ((int*) ph->buffer)[14];   /* UP, pointer id */

      if (ph->padaction == 1) {
         ph->touchcnt  = touchcnt = 0;
      } else {
         ph->touchcnt  = ((int*) ph->buffer)[15];   /* number of touches */
         touchcnt = ph->touchcnt;

         for (int i=0; i<ph->touchcnt; i++) {
           float px, py;
           int ptrid;
           ptrid = ((int*) ph->buffer)[16+3*i];     /* pointer id */
           px  = ((float*) ph->buffer)[17+3*i];     /* X pixel */
           py  = ((float*) ph->buffer)[18+3*i];     /* Y pixel */

//        printf("PID:%2d, X:%4.3f, Y:%4.3f, ", ptrid, px, py);

           /* scale coords to be in inches rather than pixels */
           ph->padx[i] = px * xinvdpi;
           ph->pady[i] = py * yinvdpi;
         }
      }
//      printf("\n");

      break;
  } // end switch (packtype)


  if (packtype == PACKET_ORIENT) {
    rx = -ph->rx;
    ry = -(ph->rz-180); // Renormalize Android X angle from 0:360deg to -180:180
    rz =  ph->ry;
    tx = 0.0;
    ty = 0.0;
    tz = 0.0;
  }

  if (packtype == PACKET_TOUCH) {
    padaction = ph->padaction;
    upid = ph->upid;

    for (int i=0; i<ph->touchcnt; i++) {
      padx[i] = ph->padx[i];
      pady[i] = ph->pady[i];
    }
  }

#if 1
  // get absolute values of axis forces for use in
  // null region processing and min/max comparison tests
  float t_null_region = 0.01;
  float r_null_region = 10.0;
  float atx = fabs(tx);
  float aty = fabs(ty);
  float atz = fabs(tz);
  float arx = fabs(rx);
  float ary = fabs(ry);
  float arz = fabs(rz);

  // perform null region processing
  if (atx > t_null_region) {
    tx = ((tx > 0) ? (tx - t_null_region) : (tx + t_null_region));
  } else {
    tx = 0;
  }
  if (aty > t_null_region) {
    ty = ((ty > 0) ? (ty - t_null_region) : (ty + t_null_region));
  } else {
    ty = 0;
  }
  if (atz > t_null_region) {
    tz = ((tz > 0) ? (tz - t_null_region) : (tz + t_null_region));
  } else {
    tz = 0;
  }
  if (arx > r_null_region) {
    rx = ((rx > 0) ? (rx - r_null_region) : (rx + r_null_region));
  } else {
    rx = 0;
  }
  if (ary > r_null_region) {
    ry = ((ry > 0) ? (ry - r_null_region) : (ry + r_null_region));
  } else {
    ry = 0;
  }
  if (arz > r_null_region) {
    rz = ((rz > 0) ? (rz - r_null_region) : (rz + r_null_region));
  } else {
    rz = 0;
  }
#endif

  return 1;
} // end of mobile_listener_poll

// ------------------------------------------------------------------------

static int mobile_listener_destroy(void *voidhandle) {
  mobilehandle *ph = (mobilehandle *) voidhandle;

#if defined(_MSC_VER)
  closesocket(ph->sockfd); /* close the socket */
#else
  close(ph->sockfd); /* close the socket */
#endif
  free(ph);
  return 0;
}

// ------------------------------------------------------------------------

// constructor
Mobile::Mobile(VMDApp *vmdapp)
	: UIObject(vmdapp) {
  mobile = NULL;
  port = 3141; // default UDP port to use

  packtimer = wkf_timer_create();
  wkf_timer_start(packtimer);

  touchinprogress = 0;
  touchcount = 0;
  touchmode = ROTATE;
  touchscale = 1.0;
  touchscalestartdist = 0;
  touchrotstartangle = 0;
  touchdeltaX = 0;
  touchdeltaY = 0;
  buttonDown = 0;
  reset();
}

// ------------------------------------------------------------------------

// destructor
Mobile::~Mobile(void) {
  wkf_timer_destroy(packtimer);

  for (int i=0; i<clientNick.num();i++)
  {
    delete clientNick[i];
    delete clientIP[i];
  }

  // clean up the client list
//  while (clientList.num() > 0)
//  {
//     MobileClientList *ptr = clientList.pop();
//     delete ptr;
//  }

  if (mobile != NULL)
    mobile_listener_destroy(mobile);
}


// ------------------------------------------------------------------------
bool Mobile::isInControl(JString* nick, JString* ip, const int packtype)
{
//   fprintf(stderr, "isInControl.start: %s, %s\n", (const char*)*nick, (const char *)*ip);
  int i;
  for (i=0; i < clientNick.num(); i++) {
    if (*nick == *(clientNick[i]) && *ip == *(clientIP[i])) {
      // xxx: update the timer here?
      break;
    }
  }

  if (i < clientNick.num()) // we found them!
  {
    // was this a disconnect?
    if (packtype == PACKET_DISCONNECT) {
      removeClient(i);
      return false;
    }
    return clientActive[i];
  }  else {
    JString *tmpNick, *tmpIp;
    tmpNick = new JString(*nick);
    tmpIp = new JString(*ip);
//   fprintf(stderr, "isInControl: Adding %s, %s\n", (const char *)*tmpNick, (const char *)*tmpIp);
    // we didn't find this particular IP/nick combination.  Let's add it.
    if (clientNick.num() == 0) // there weren't any before
    {
      addNewClient(tmpNick, tmpIp, true);  // make this client in control
      return true;
    } else {
      addNewClient(tmpNick, tmpIp, false);  // just a new client.. not in control
      return false;
    }
  }
  return false; // won't ever get here
}
// ------------------------------------------------------------------------
/////////////////////// virtual routines for UI init/display  /////////////
   
// reset the Mobile to original settings
void Mobile::reset(void) {
  // set the default motion mode and initialize button state
  move_mode(OFF);

  // set the maximum animate stride allowed to 20 by default
  set_max_stride(20);

  // set the default translation and rotation increments
  // these really need to be made user modifiable at runtime
  transInc = 1.0f / 25000.0f;
    rotInc = 1.0f /   200.0f;
  scaleInc = 1.0f / 25000.0f;
   animInc = 1.0f /     1.0f;
}

// ------------------------------------------------------------------------
// update the display due to a command being executed.  Return whether
// any action was taken on this command.
// Arguments are the command type, command object, and the 
// success of the command (T or F).
int Mobile::act_on_command(int type, Command *cmd) {
  return FALSE; // we don't take any commands presently
}
  int iCounter = 0;

// ------------------------------------------------------------------------
// check for an event, and queue it if found.  Return TRUE if an event
// was generated.
int Mobile::check_event(void) {
  float tx, ty, tz, rx, ry, rz;
  int touchid[16];
  float padx[16], pady[16];
  
  int padaction, upid, buttons, touchcnt;
  int buttonchanged;
  int win_event=FALSE;
  int packtype;
  JString incIP, nick;
  bool inControl = false;

  // for use in UserKeyEvent() calls
//  DisplayDevice::EventCodes keydev=DisplayDevice::WIN_KBD;

  // explicitly initialize event state variables
  rx=ry=rz=tx=ty=tz=buttons=padaction=upid=0;
  memset(touchid, 0, sizeof(touchid));
  memset(padx, 0, sizeof(padx));
  memset(pady, 0, sizeof(pady));
  touchcnt=0;

  // process as many events as we can to prevent a packet backlog 
  while (moveMode != OFF && 
         mobile_listener_poll(mobile, rx, ry, rz, tx, ty, tz, padaction, upid,
                              touchcnt, touchid, padx, pady, buttons, packtype,
                              incIP, nick)) 
  {
//fprintf(stderr, "inside while. %s, %s\n", (const char *)nick, (const char *)incIP);
    win_event = TRUE;

    // let's figure out who this is, and whether or not they are in
    // control

    if (isInControl(&nick, &incIP, packtype))
    {
      DisplayDevice::EventCodes keydev=DisplayDevice::WIN_KBD;
      inControl = true;

      // find which buttons changed state
      buttonchanged = buttons ^ buttonDown; 

        // XXX change hardcoded numbers and support >3 buttons
      if (buttonchanged) {
         // for normal buttons, we want the down event
        if (buttonchanged == (1<<0) && (buttonchanged & buttons)) {
           runcommand(new UserKeyEvent(keydev, '0', (int) DisplayDevice::AUX));
        }
        if (buttonchanged == (1<<1) && (buttonchanged & buttons)) {
           runcommand(new UserKeyEvent(keydev, '1', (int) DisplayDevice::AUX));
        }
        if (buttonchanged == (1<<2) && (buttonchanged & buttons)) {
           runcommand(new UserKeyEvent(keydev, '2', (int) DisplayDevice::AUX));
        }
        if (buttonchanged == (1<<3) && (buttonchanged & buttons)) {
           runcommand(new UserKeyEvent(keydev, '3', (int) DisplayDevice::AUX));
        }


        if (buttonchanged == (1<<31)) {         // 'reset view' 
          if (buttonchanged & buttons) {       // get it on the 'down' event.
            app->scene_resetview();
          }
        }
      }

#if 0
       printf("Touchpad action: %d upid %d", padaction, upid);
       for (int i=0; i<touchcnt; i++) {
         printf("ID[%d] x: %.2f y: %.2f ",
                i, padx[i], pady[i]);
       }
       printf("\n");
#endif

      if (padaction != EVENT_NON_TOUCH) {

      // detect end of a touch event
      if (touchcnt < touchcount || 
           padaction == EVENT_TOUCH_UP || padaction == EVENT_TOUCH_SOMEUP) {
//         fprintf(stderr,"<(a:%d,b:%d)", touchcnt, touchcount);
        touchinprogress = 0;
        touchmode = ROTATE;
        touchcount = 0;
        touchstartX = 0;
        touchstartY = 0;
        touchdeltaX = 0;
        touchdeltaY = 0;
        touchscale = 1.0;
        touchscalestartdist = 0;
        touchrotstartangle = 0;
      }
    
      // detect a touch starting event 
      if (touchcnt > touchcount ||
           padaction == EVENT_TOUCH_DOWN ||
           padaction == EVENT_TOUCH_SOMEDOWN) {
//         fprintf(stderr,">(a:%d,b:%d)", touchcnt, touchcount);
        touchcount = touchcnt;
        touchstartX = 0;
        touchstartY = 0;
        touchdeltaX = 0;
        touchdeltaY = 0;
        touchscale = 1.0;
        touchscalestartdist = 0;
        touchrotstartangle = 0;

   // printf("Touchcount: %d\n", touchcount);
        if (touchcount == 1) {
   // printf("Start rotate..\n");
          touchinprogress=1;
          touchmode = ROTATE;
          touchstartX = padx[0];
          touchstartY = pady[0];
        } else if (touchcount == 2) {
          touchinprogress=1;
          touchstartX = (padx[0] + padx[1]) * 0.5f;
          touchstartY = (pady[0] + pady[1]) * 0.5f;

          float dx = padx[1] - padx[0];
          float dy = pady[1] - pady[0];
          touchscalestartdist = sqrt(dx*dx + dy*dy) + 0.00001;
          if (touchscalestartdist > 0.65) { 
            touchrotstartangle = atan2(dx, -dy) + VMD_PI;
   // printf("Start scale.. dist: %.2f  angle: %.2f\n", touchscalestartdist, touchrotstartangle);
            touchmode = SCALEROTZ;
          } else {
   // printf("Start translate.. dist(%.2f)\n", touchscalestartdist);
            touchmode = TRANSLATE;
          }
        }
      }

      if (touchinprogress && padaction == EVENT_TOUCH_MOVE) {
        if (touchmode == ROTATE) {
          touchdeltaX = padx[0] - touchstartX;
          touchdeltaY = pady[0] - touchstartY;
        } else if (touchmode == SCALEROTZ) {
          // only move the structure if we're in move mode,
          // in animate mode we do nothing...
          if (moveMode == MOVE) {
            float dx = padx[1] - padx[0];
            float dy = pady[1] - pady[0];
            float dist = sqrtf(dx*dx + dy*dy);
     
            // Only scale if the scale changes by at least 1%
            float newscale = (dist / touchscalestartdist) / touchscale;
            if (fabs(newscale - 1.0) > 0.01) {
              touchscale *= newscale;
              app->scene_scale_by(newscale);
            }

            // Only rotate if the angle update is large enough to make
            // it worthwhile, otherwise we get visible "jitter" from noise
            // in the touchpad coordinates.  Currently, we only rotate if
            // the rotation magnitude is greater than a quarter-degree
            float newrotangle = atan2(dx, -dy) + VMD_PI;
            float rotby = (newrotangle-touchrotstartangle)*180/VMD_PI;
            if (fabs(rotby) > 0.25) {
              app->scene_rotate_by(-rotby, 'z');
              touchrotstartangle=newrotangle;
            }
          }
        } else if (touchmode == TRANSLATE) {
          touchdeltaX = ((padx[0]+padx[1])*0.5) - touchstartX;
          touchdeltaY = ((pady[0]+pady[1])*0.5) - touchstartY;
        }
      }

      }

      // update button status for next time through
      buttonDown = buttons;
    }  // end of isInControl

    // restart last-packet timer
    wkf_timer_start(packtimer);
  }           // end while (moveMode != OFF && mobile_listener_poll())

//  if ((++iCounter % 1000) == 0 ) fprintf(stderr,"p%d,m%d;", touchinprogress,touchmode);

  // xxx: this next check really needs to be done on a per-client basis and 
  // non responsive clients should be kicked out
  // check for dropped packets or mobile shutdown and 
  // halt any ongoing events if we haven't heard from the
  // client in over 1 second.  
  if (!win_event && wkf_timer_timenow(packtimer) > 3.0) {
    touchinprogress = 0;
    touchmode = ROTATE;
    touchcount = 0;
    touchstartX = 0;
    touchstartY = 0;
    touchdeltaX = 0;
    touchdeltaY = 0;
    touchscalestartdist = 0;
    touchrotstartangle = 0;
  }

  if (touchinprogress) {
    if (moveMode == MOVE) {
      if (touchmode == ROTATE) {
//         fprintf(stderr,"+");
        // Motion in Android "X" rotates around VMD Y axis...
        app->scene_rotate_by(touchdeltaY*0.5, 'x');
        app->scene_rotate_by(touchdeltaX*0.5, 'y');
      } else if (touchmode == TRANSLATE) {
        app->scene_translate_by(touchdeltaX*0.005, -touchdeltaY*0.005, 0);
      }
    } else if (moveMode == ANIMATE) {
      if (fabsf(touchdeltaX) > 0.25f) {
#if 0
        // exponential input scaling
        float speed = fabsf(expf(fabsf((fabsf(touchdeltaX) * animInc) / 1.7f))) - 1.0f;
#else
        // linear input scaling
        float speed = fabsf(touchdeltaX) * animInc;
#endif

        if (speed > 0) {
          if (speed < 1.0)
            app->animation_set_speed(speed);
          else
            app->animation_set_speed(1.0f);

          int stride = 1;
          if (fabs(speed - 1.0) > (double) maxstride)
            stride = maxstride;
          else
            stride = 1 + (int) fabs(speed-1.0);
          if (stride < 1)
            stride = 1;
          app->animation_set_stride(stride);

          if (touchdeltaX > 0) {
            app->animation_set_dir(Animation::ANIM_FORWARD1);
          } else {
            app->animation_set_dir(Animation::ANIM_REVERSE1);
          }
        } else {
          app->animation_set_dir(Animation::ANIM_PAUSE);
          app->animation_set_speed(1.0f);
        }
      } else {
        app->animation_set_dir(Animation::ANIM_PAUSE);
        app->animation_set_speed(1.0f);
      }
    }
  } else { 
//     if (!inControl) fprintf(stderr,"-");
//     if (!touchinprogress) fprintf(stderr,"|");
     } 

  if (win_event) {
    return TRUE;
  } else {
    return FALSE; // no events to report
  }
} // end of Mobile::check_event(void) {

// ------------------------------------------------------------------------
///////////// public routines for use by text commands etc

const char* Mobile::get_mode_str(MoveMode mm) {
  const char* modestr;

  switch (mm) {
    default:
    case OFF:         modestr = "off";        break;
    case MOVE:        modestr = "move";       break;
    case ANIMATE:     modestr = "animate";    break;
    case TRACKER:     modestr = "tracker";    break;
    case USER:        modestr = "user";       break;
  }

  return modestr;
}

// ------------------------------------------------------------------------
int Mobile::get_port () {
  return port;
}

// ------------------------------------------------------------------------
int Mobile::get_move_mode () {
  return moveMode;
}

// ------------------------------------------------------------------------
void  Mobile::get_client_list (ResizeArray <JString*>* &nick, 
                         ResizeArray <JString*>* &ip, ResizeArray <bool>* &active)
{
  nick = &clientNick;
  ip = &clientIP;
  active = &clientActive;
}

// ------------------------------------------------------------------------
int Mobile::set_activeClient(const char *nick, const char *ip)
{
//   fprintf(stderr, "in set_activeClient.  nick: %s, ip: %s\n", nick, ip);
   // find the user with the given nick and ip
  bool found = false;
  int i;
  for (i=0; i<clientNick.num();i++)
  {
    if (*(clientNick[i]) == nick) {
      // we've found the right nick.  Now let's check the IP
      if (*(clientIP[i]) == ip) {
        found = true;
        break;
      }
    }
  }
   
  if (found) { 
    // First, run through clientActive and turn everyone off.
    for (int j=0; j<clientActive.num();j++)
    {
       clientActive[j] = false;
    }

    // turn off any movements that might have been going on
    touchinprogress = 0;
    touchmode = ROTATE;
    touchcount = 0;
    touchstartX = 0;
    touchstartY = 0;
    touchdeltaX = 0;
    touchdeltaY = 0;
    touchscalestartdist = 0;
    touchrotstartangle = 0;

    // set this one client to active.
    clientActive[i] = true;

    return true;
  } else {
    return false;
  }
}

// ------------------------------------------------------------------------

void Mobile::get_tracker_status(float &tx, float &ty, float &tz,
                                float &rx, float &ry, float &rz, 
                                int &buttons) {
  tx =  trtx * transInc;
  ty =  trty * transInc;
  tz = -trtz * transInc;
  rx =  trrx * rotInc;
  ry =  trry * rotInc;
  rz = -trrz * rotInc;
  buttons = trbuttons;
}

// ------------------------------------------------------------------------

// set the Mobile move mode to the given state; return success
int Mobile::move_mode(MoveMode mm) {
  // change the mode now
  moveMode = mm;

  if (moveMode != OFF && !mobile) {
    mobile = mobile_listener_create(port);
    if (mobile == NULL) {
      msgErr << "Failed to open mobile port " << port 
             << ", move mode disabled" << sendmsg;
      moveMode = OFF;
    } else {
      msgInfo << "Opened mobile port " << port << sendmsg;
    }
  }

  /// clear out any remaining tracker event data if we're not in that mode
  if (moveMode != TRACKER) {
    trtx=trty=trtz=trrx=trry=trrz=0.0f; 
    trbuttons=0;
  }
//fprintf(stderr,"Triggering command due to mode change\n");
  runcommand(new MobileStateChangedEvent());

  return TRUE; // report success
}   // end of Mobile::move_mode

// ------------------------------------------------------------------------

// set the incoming UDP port (closing the old one if needed)
int Mobile::network_port(int newport) {

  if (mobile != NULL) {
    mobile_listener_destroy(mobile);

    mobile = mobile_listener_create(newport);
    if (mobile == NULL) {
      msgErr << "Failed to open mobile port " << newport 
             << ", move mode disabled" << sendmsg;
      moveMode = OFF;
    } else {
      port = newport;
//fprintf(stderr,"Triggering command due to port change\n");
      msgInfo << "Opened mobile port " << port << sendmsg;
    }
  }
  runcommand(new MobileStateChangedEvent());

  return TRUE; // report success
}     // end of Mobile::network_port


// ------------------------------------------------------------------------
int  Mobile::addNewClient(JString* nick,  JString* ip, const bool active)
{
//  fprintf(stderr, "Adding %s, %s, %d\n", (const char*)*nick, (const char*)*ip, active);
  clientNick.append(nick);
  clientIP.append(ip);
  clientActive.append(active);

//fprintf(stderr,"Triggering command due to addNewClient\n");
  runcommand(new MobileStateChangedEvent());
  return 0;
}     // end of Mobile::addNewClient

// ------------------------------------------------------------------------
int  Mobile::removeClient(const int num)
{
  delete clientNick[num];
  clientNick.remove(num);

  delete clientIP[num];
  clientIP.remove(num);

  clientActive.remove(num);

  // is there only one left?  If so, make them active
  if (clientActive.num() == 1)
  {
    clientActive[0] = true;
  }

//fprintf(stderr,"Triggering command due to removeClient\n");
  runcommand(new MobileStateChangedEvent());
  return 0;
}



