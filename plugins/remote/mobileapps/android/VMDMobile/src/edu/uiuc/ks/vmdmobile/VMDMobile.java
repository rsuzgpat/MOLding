/***************************************************************************
 *cr
 *cr            (C) Copyright 2011 The Board of Trustees of the
 *cr                        University of Illinois
 *cr                         All Rights Reserved
 *cr
 ***************************************************************************/
package edu.uiuc.ks.vmdmobile;


import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.util.Log;
import android.util.DisplayMetrics;
import android.hardware.Sensor;
import android.hardware.SensorManager;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.view.WindowManager;
import android.view.View.OnClickListener;
import android.view.View.OnTouchListener;
import android.view.MotionEvent;
import android.view.View;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.EditText;
//import android.widget.ToggleButton;
import android.widget.Button;

import org.metalev.multitouch.controller.MultiTouchController.PointInfo;

import java.io.*;
import java.net.*;

public class VMDMobile extends Activity implements SensorEventListener {
    final String tag = "VMDMobile";
    final String prefFile = "mainprefs";

    // athine
//    public static final String DEFAULT_VMD_IP = "130.126.120.165";
    public static final String DEFAULT_VMD_IP = "127.0.0.1";
    public static final int    DEFAULT_VMD_PORT = 3141;

    public static final int API_VERSION = 8;

    final int DEVICE_STATE = 1;
    final int TOUCH_STATE = 2;
    final int HEART_BEAT = 3;
    final int CONNECT_MSG = 4;
    final int DISCONNECT_MSG = 5;
    final int BUTTON_EVENT = 6;

    InetAddress addr;
    DatagramSocket skt;

    SensorManager sm = null;
    
//    ToggleButton toggleSensorSend = null;
//    ToggleButton toggleTouchSend = null;
//    ToggleButton button0 = null;
    Button button0 = null;
    Button button1 = null;
    Button button2 = null;
    Button button3 = null;

    MultiTouchPad touchPad = null;

    TextView console = null;
    TextView ipInfo = null;

    SharedPreferences mPrefs = null;
    float [] orientation;
    float [] accel;
    float [] magField;
    float [] gyroscope;
    float [] Rmat;
    float [] Imat;

    int i;

    int buttonState = 0;

    boolean sendingOrient = false;
    boolean sendingTouch = false;

    int screenWidth;
    int screenHeight;
    float xdpi;
    float ydpi;

    long lastTime = System.currentTimeMillis();

    private static final int INVALID_POINTER = -1;
    private int activePointer = INVALID_POINTER;

    // lengths in bytes
    private static final int headerLength = 24;
    private static final int sensorPayloadLength = 36 + 36;
    private static final int touchPayloadLength = 40;
    private static final int touchPointsSupported = 5;
    
    private static final int BUTTON_DATA_SIZE = headerLength + 12;
    private static final int HEARTBEAT_DATA_SIZE = headerLength + 12;
    private static final int CONNECT_DATA_SIZE = headerLength + 12;
    private static final int DISCONNECT_DATA_SIZE = headerLength + 12;
    private static final int SENSOR_DATA_SIZE = headerLength + 
                                                        sensorPayloadLength;
    private static final int TOUCH_DATA_SIZE = headerLength + touchPayloadLength
                                                  + touchPointsSupported * 12;

    private static final int MAX_PACKET_SIZE = 2048;  // arbitrary
    private byte [] data;
    private byte [] buttonData;
    private byte [] heartBeatData;
    private int sequenceNumber = 0;
    private DatagramPacket pkt = null;

    private HeartBeat m_heartBeat;
    private int HEARTBEATMILLIS = 1000;

    private PointInfo oldTouchPoints = new PointInfo();

// -------------------------------------------------------------
    // handles up to 32 buttons
    private void setButtonState(final int id, final boolean value)
    {
       int oldState = buttonState;
       // buttonState is the int
       if (value)
       {
          buttonState |= (1 << id);
       } else {
          buttonState &= ~(1 << id);
       }
       if (oldState != buttonState)
       {
          sendButtonState();
       }
//       logConsole("button" + id + ",val: " + value +"," + buttonState);
    }  // end of setButtonState
 
   // ----------------------------------------------------------------
   private void openUDPSocket()
   {
      try {
         addr = InetAddress.getByName(mPrefs.getString("ipEntry",
                                                       DEFAULT_VMD_IP));
         skt = new DatagramSocket(
                         Integer.parseInt(mPrefs.getString("portEntry",
                         "" + DEFAULT_VMD_PORT)));
         // broadcasting UDP doesn't seem to work on 130.126.120.255.
         // hard to say for positive that this is true, but it seems to
         // fail using the technique at:
         //   http://code.google.com/p/boxeeremote/wiki/AndroidUDP
//         skt.setBroadcast(true);
         pkt = new DatagramPacket( data, MAX_PACKET_SIZE, addr,
                         Integer.parseInt(mPrefs.getString("portEntry",
                         "" + DEFAULT_VMD_PORT)));
//         Log.d(tag, "openUDPSocket: Opened socket and created packet properly");
         ipInfo.setText("VMD Server: " + 
               mPrefs.getString("ipEntry", "") + ":" + 
               mPrefs.getString("portEntry", ""));
      } catch (Exception e) {
         logConsole("InitError: " + e);
         ipInfo.setText(e.toString() + ": Invalid VMD Server: " + 
               mPrefs.getString("ipEntry", "") + ":" + 
               mPrefs.getString("portEntry", ""));
//         Log.d(tag, "openUDPSocket:" + e.toString());
      }
   } // end of openUDPSocket

// -------------------------------------------------------------
   private void startSensorRecording()
   {
      if (!sendingOrient)
      {
         Sensor aSensor = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
         sm.registerListener(this,aSensor,SensorManager.SENSOR_DELAY_FASTEST);

//         Sensor oSensor = sm.getDefaultSensor(Sensor.TYPE_ORIENTATION);
//         sm.registerListener(this,oSensor,SensorManager.SENSOR_DELAY_FASTEST);

         Sensor mSensor = sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);
         sm.registerListener(this,mSensor,SensorManager.SENSOR_DELAY_FASTEST);

         Sensor gSensor = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE);
         sm.registerListener(this,gSensor,SensorManager.SENSOR_DELAY_FASTEST);

         sendingOrient = true;
      }
   } // end of startSensorRecording

// -------------------------------------------------------------
   private void startSending()
   {
      if (skt == null || skt.isClosed())
      {
         openUDPSocket();
      }

      if (skt == null || skt.isClosed())
      {
         // something didn't work
         ipInfo.setText("Invalid VMD Server: " + 
               mPrefs.getString("ipEntry", "") + ":" + 
               mPrefs.getString("portEntry", ""));
         return;
      }
   
      sendConnectMsg();

      if (m_heartBeat != null)
      {
         m_heartBeat.setContinue(false);
         try {
            m_heartBeat.interrupt();
         } catch(SecurityException e) { /* don't care */ }
         m_heartBeat = null;
      } 
      m_heartBeat = new HeartBeat(HEARTBEATMILLIS, this);
      m_heartBeat.start();
      sendingTouch = true;
   }

// -------------------------------------------------------------
   private void stopAllSending()
   {
      if (m_heartBeat != null)
      {
         m_heartBeat.setContinue(false);
         try {
            m_heartBeat.interrupt();
         } catch(SecurityException e) { /* don't care */ }
         m_heartBeat = null;
      }

      // foobar.  Send goodbye message
      sendDisconnectMsg();

      stopSensorRecording();
      sendingOrient = sendingTouch = false;
//      if (toggleTouchSend != null) toggleTouchSend.setChecked(false);
//      if (toggleSensorSend != null) toggleSensorSend.setChecked(false);
      if (skt != null && !skt.isClosed())
      {
         skt.close();
      }
   }

// -------------------------------------------------------------
   private void stopSensorRecording()
   {
      sm.unregisterListener(this);
      sendingOrient = false;;
   }

   // -----------------------------------------------------------------
   // prepare 'data' for shipment via UDP
   private void packDeviceState()
   {
       int caret = headerLength;

       // pack payload description (DEVICE_STATE, in this case)
       packInt(DEVICE_STATE, data, caret);
       caret += 4;   // sizeof(int)

       packInt(buttonState, data, caret);
       caret += 4;   // sizeof(int)

       // strictly monotonically increasing number
       packInt(sequenceNumber++, data, caret );
       caret += 4;   // sizeof(int)


       // orientation
       packFloatArray(orientation, data, caret );
       caret += orientation.length * 4;  // 4 is sizeof(float)

       packFloatArray(accel, data, caret);
       caret += accel.length * 4;  // 4 is sizeof(float)


       packFloatArray(Rmat, data, caret);
       caret += Rmat.length * 4;  // 4 is sizeof(float)

   } // end of packDeviceState

   // -----------------------------------------------------------------
    // prepare 'data' for shipment via UDP
    private void packTouchState(PointInfo currTouchPoints, final int width, final int height)
    {
       int caret = headerLength;

       int numPoints = Math.min(touchPointsSupported, currTouchPoints.getNumTouchPoints());

       // pack payload description (DEVICE_STATE, in this case)
       packInt(TOUCH_STATE, data, caret);
       caret += 4;   // sizeof(int)

       packInt(buttonState, data, caret);
       caret += 4;   // sizeof(int)

       // strictly monotonically increasing number
       packInt(sequenceNumber++, data, caret );
       caret += 4;   // sizeof(int)

       packFloat(xdpi, data, caret);
       caret += 4;   // sizeof(float)

       packFloat(ydpi, data, caret);
       caret += 4;   // sizeof(float)

       packInt(width, data, caret);
       caret += 4;   // sizeof(int)

       packInt(height, data, caret);
       caret += 4;   // sizeof(int)

       packInt(currTouchPoints.getAction() & MotionEvent.ACTION_MASK, 
                                                          data, caret);
       caret += 4;   // sizeof(int)

       if ((currTouchPoints.getAction() & MotionEvent.ACTION_MASK) == 
                                         MotionEvent.ACTION_POINTER_UP)
       {
          packInt((currTouchPoints.getAction() & 
                   MotionEvent.ACTION_POINTER_INDEX_MASK) 
                                    >> MotionEvent.ACTION_POINTER_INDEX_SHIFT, 
                   data, caret); 
          caret += 4;   // sizeof(int)

       } else {
          packInt(0, data, caret); 
          caret += 4;   // sizeof(int)
       }

       packInt(numPoints, data, caret);
       caret += 4;   // sizeof(int)

       float[] xs = currTouchPoints.getXs();
       float[] ys = currTouchPoints.getYs();
       int[] pids = currTouchPoints.getPointerIds();

       for (int i = 0; i < numPoints; i++)
       {
          packInt(pids[i], data, caret);
          caret += 4;   // sizeof(int)

          packFloat(xs[i], data, caret);
          caret += 4;   // sizeof(float)

          packFloat(ys[i], data, caret);
          caret += 4;   // sizeof(float)
       }
    } // end of packTouchState

   // ----------------------------------------------------------------
    /** Called when the activity is first created. */
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
//        Log.d(tag, "onCreate start");
       // get reference to SensorManager
        setContentView(R.layout.main);

        sm = (SensorManager) getSystemService(Context.SENSOR_SERVICE);

        i = 0;

        orientation = new float[3];
        accel = new float[3];
        gyroscope = new float[3];
        magField = new float[3];

        Rmat = new float[9];
        Imat = new float[9];
        data = new byte[MAX_PACKET_SIZE];
        heartBeatData = new byte[HEARTBEAT_DATA_SIZE];
        buttonData = new byte[BUTTON_DATA_SIZE];

        console = (TextView) findViewById(R.id.console);
        ipInfo = (TextView) findViewById(R.id.ipinfo);

        mPrefs = getSharedPreferences(prefFile, MODE_PRIVATE);

//        hasMulti = hasMultiTouch();

        configureGUIitems();
        
// ----------------------------------------

        // keep the screen on while this application is in the foreground
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        DisplayMetrics metrics = new DisplayMetrics();
        getWindowManager().getDefaultDisplay().getMetrics(metrics);
        screenWidth = metrics.widthPixels;
        screenHeight = metrics.heightPixels;
        xdpi = metrics.xdpi;
        ydpi = metrics.ydpi;
    }

// -----------------------------------------------------------------

//    private boolean hasMultiTouch()
//    {
 //      try {
  //      MotionEvent.class.getMethod("getPointerCount", new Class[] {});
   //     MotionEvent.class.getMethod( "getPointerId", new Class[] { int.class });
    //    MotionEvent.class.getMethod( "getX", new Class[] { int.class });
     //   MotionEvent.class.getMethod( "getY", new Class[] { int.class });
//        return true;
 //      } catch (NoSuchMethodException nsme) {
  //      return false;
   //    }
//    }

// -----------------------------------------------------------------

    private void configureGUIitems()
    {

// ----------------------------------------
/*
        toggleSensorSend = (ToggleButton) findViewById(R.id.toggleSensorSend);
        toggleSensorSend.setOnClickListener(new OnClickListener() {
            public void onClick(View v) {
                // Perform action on clicks
                if (toggleSensorSend.isChecked()) {
                   startSensorRecording();
//                   startSending();
                } else {
                   stopSensorRecording();
                }
            }
        });
// ----------------------------------------

        button0 = (ToggleButton) findViewById(R.id.button0);
        button0.setOnClickListener(new OnClickListener() {
            public void onClick(View v) {
                // Perform action on clicks
                if (button0.isChecked()) {
                   setButtonState(0, true);
                } else {
                   setButtonState(0, false);
                }
            }
        });
*/

// ----------------------------------------
        button0 = (Button) findViewById(R.id.button0);
        button0.setOnTouchListener(new OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
//               logConsole("action is: " + event.getAction());
//               logConsole("" + MotionEvent.ACTION_DOWN + "," + MotionEvent.ACTION_MOVE + "," + event.getAction());
                if ( event.getAction() == (MotionEvent.ACTION_DOWN) ||
                     event.getAction() == (MotionEvent.ACTION_MOVE)) {

                   setButtonState(0, true);
                } else {
//               logConsole("setting button to false");
                   setButtonState(0, false);
                }
               return false;
            }
        });

// ----------------------------------------
        button1 = (Button) findViewById(R.id.button1);
        button1.setOnTouchListener(new OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
//               logConsole("action is: " + event.getAction());
//               logConsole("" + MotionEvent.ACTION_DOWN + "," + MotionEvent.ACTION_MOVE + "," + event.getAction());
                if ( event.getAction() == (MotionEvent.ACTION_DOWN) ||
                     event.getAction() == (MotionEvent.ACTION_MOVE)) {

                   setButtonState(1, true);
                } else {
//               logConsole("setting button to false");
                   setButtonState(1, false);
                }
               return false;
            }
        });

// ----------------------------------------
        button2 = (Button) findViewById(R.id.button2);
        button2.setOnTouchListener(new OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
//               logConsole("action is: " + event.getAction());
//               logConsole("" + MotionEvent.ACTION_DOWN + "," + MotionEvent.ACTION_MOVE + "," + event.getAction());
                if ( event.getAction() == (MotionEvent.ACTION_DOWN) ||
                     event.getAction() == (MotionEvent.ACTION_MOVE)) {

                   setButtonState(2, true);
                } else {
//               logConsole("setting button to false");
                   setButtonState(2, false);
                }
               return false;
            }
        });

// ----------------------------------------
        button3 = (Button) findViewById(R.id.button3);
        button3.setOnTouchListener(new OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
//               logConsole("action is: " + event.getAction());
//               logConsole("" + MotionEvent.ACTION_DOWN + "," + MotionEvent.ACTION_MOVE + "," + event.getAction());
                if ( event.getAction() == (MotionEvent.ACTION_DOWN) ||
                     event.getAction() == (MotionEvent.ACTION_MOVE)) {

                   setButtonState(3, true);
                } else {
//               logConsole("setting button to false");
                   setButtonState(3, false);
                }
               return false;
            }
        });

// ----------------------------------------
        touchPad = (MultiTouchPad) findViewById(R.id.touchPad);
        touchPad.registerApp(this);
/*
        touchPad.setOnTouchListener(new OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
               return touchPadActivity(event);
            }
        });
        */

    } // end of configureGUIitems

   // ----------------------------------------------------------------
   public boolean sendingTouch() { return sendingTouch; }
   // ----------------------------------------------------------------
   public void sendDisconnectMsg() {
      try {
         packInt(DISCONNECT_MSG, data, headerLength);

         packInt(buttonState, data, headerLength+4);
         packInt(sequenceNumber++, data, headerLength+8 );
         
         packAndSend(data, DISCONNECT_DATA_SIZE);
      } catch (Exception e) {
         StringWriter errstr = new StringWriter();
         PrintWriter pw = new PrintWriter(errstr);
         e.printStackTrace(pw);
         logConsole( errstr.toString());
//         Log.d(tag, e.toString());
      }
   }
   // ----------------------------------------------------------------
   public void sendConnectMsg() {
      try {
         packInt(CONNECT_MSG, data, headerLength);
         packInt(buttonState, data, headerLength+4);
         packInt(sequenceNumber++, data, headerLength+8 );

         packAndSend(data, CONNECT_DATA_SIZE);
      } catch (Exception e) {
         StringWriter errstr = new StringWriter();
         PrintWriter pw = new PrintWriter(errstr);
         e.printStackTrace(pw);
         logConsole( errstr.toString());
//         Log.d(tag, e.toString());
      }
   }
   // ----------------------------------------------------------------
   public void sendHeartBeat() {
      try {
         // the HEARTBEAT msg identifier has already been packed
         // at position 'headerLength' of heartBeatData
//         packInt(buttonState, heartBeatData, headerLength+4);
//         packInt(sequenceNumber++, data, headerLength+8 );
         packTouchState(oldTouchPoints, touchPad.getWidth(), touchPad.getHeight());
         packInt(HEART_BEAT, data, headerLength);

         packAndSend(data, TOUCH_DATA_SIZE);
//         packAndSend(heartBeatData, HEARTBEAT_DATA_SIZE);
      } catch (Exception e) {
         StringWriter errstr = new StringWriter();
         PrintWriter pw = new PrintWriter(errstr);
         e.printStackTrace(pw);
         logConsole( errstr.toString());
//         Log.d(tag, e.toString());
      }
   }

   // ----------------------------------------------------------------
   public void sendButtonState() {
      try {
         // the BUTTON_EVENT msg identifier has already been packed
         // at position 'headerLength' of buttonData
         packInt(buttonState, buttonData, headerLength+4);
         packInt(sequenceNumber++, buttonData, headerLength+8 );
         packAndSend(buttonData, BUTTON_DATA_SIZE);
      } catch (Exception e) {
         StringWriter errstr = new StringWriter();
         PrintWriter pw = new PrintWriter(errstr);
         e.printStackTrace(pw);
         logConsole( errstr.toString());
//         Log.d(tag, e.toString());
      }
   }
   // ----------------------------------------------------------------
   public boolean sendTouchEvent(PointInfo currTouchPoints)
   {
      try {

         packTouchState(currTouchPoints, touchPad.getWidth(), touchPad.getHeight());
         
         packAndSend(data, TOUCH_DATA_SIZE);
         if (++i%25 == 0)
         {
              int numPoints = Math.min(touchPointsSupported, currTouchPoints.getNumTouchPoints());
              logConsole("i:" + i + ",numPoints:" + 
                                   String.format("%4d", numPoints));
         }

      } catch (Exception e) {
         StringWriter errstr = new StringWriter();
         PrintWriter pw = new PrintWriter(errstr);
         e.printStackTrace(pw);
//         Log.d(tag, e.toString());

         logConsole( errstr.toString());
      }
      return false;

   }

   // ----------------------------------------------------------------
   public boolean registerTouch(PointInfo currTouchPoints)
   {
      oldTouchPoints = currTouchPoints;
      if (!sendingTouch) return true;
      return sendTouchEvent(currTouchPoints);
   }

   // ----------------------------------------------------------------
    public void onSensorChanged(SensorEvent event) {
//       int sensor = event.sensor.getType();
       if (!sendingOrient) return;
       try {
        synchronized (this) {
           i++;


//            if (sensor == SensorManager.SENSOR_ORIENTATION) {
//               System.arraycopy(event.values,0,orientation,0,3);
//            }
//            else 
            switch (event.sensor.getType())
            {
               case Sensor.TYPE_ACCELEROMETER:
                  System.arraycopy(event.values,0,accel,0,3);
                  break;
               case Sensor.TYPE_ORIENTATION:
                  System.arraycopy(event.values,0,orientation,0,3);
                  break;
               case Sensor.TYPE_GYROSCOPE:
                  System.arraycopy(event.values,0,orientation,0,3);
                  break;
               case Sensor.TYPE_MAGNETIC_FIELD:
                  System.arraycopy(event.values,0,magField,0,3);
                  break;
            }

//            if (sensor == Sensor.TYPE_ACCELEROMETER) {
//               System.arraycopy(event.values,0,accel,0,3);
//            }            
//            else if (sensor == Sensor.TYPE_MAGNETIC_FIELD) {
//               System.arraycopy(event.values,0,magField,0,3);
//            }            

            // rotation matrix, 
            // http://developer.android.com/reference/android/hardware/SensorManager.html#getRotationMatrix(float[],%20float[],%20float[],%20float[])
            SensorManager.getRotationMatrix(Rmat, Imat, accel, magField);

//            SensorManager.getOrientation(Rmat, orientation);

           if (i%100 == 0)
           {
//              float r2d = (float)(180.0f/Math.PI);
//              logConsole("o:" + (int)(r2d*orientation[1]) + "," +
//                                   (int)(r2d*orientation[2]) + "," +
//                                   (int)(r2d*orientation[0]));
              logConsole("i:" + i + ",o:" + 
                                   String.format("%.2f", orientation[1]) + "," +
                                   String.format("%.2f", orientation[2]) + "," +
                                   String.format("%.2f", orientation[0]));

           }

           packDeviceState();
           packAndSend(data, SENSOR_DATA_SIZE);

        }
       } catch (Exception e) {
          StringWriter errstr = new StringWriter();
          PrintWriter pw = new PrintWriter(errstr);
          e.printStackTrace(pw);

          logConsole("" + accel[0] + "," +
                               accel[1] + "," +
                               accel[2] + "," + errstr.toString());
//          Log.d(tag, "onSensorChanged:" + e.toString());
       }
    } // onSensorChanged(SensorEvent event) {
    
   // ----------------------------------------------------------------
    public void onAccuracyChanged(int sensor, int accuracy) {
//      Log.d(tag,"onAccuracyChanged: " + sensor + ", accuracy: " + accuracy);
    }
    @Override public void onAccuracyChanged(Sensor sensor, int accuracy) {
    }
   // ----------------------------------------------------------------
    private void logConsole(final String str) {
       if (mPrefs.getBoolean("showDebug",false)) console.setText(str);
    }

   // ----------------------------------------------------------------
    @Override
    protected void onResume() {
        super.onResume();
//        Log.d(tag, "onResume start");
        logConsole("Waking up. slept " + (System.currentTimeMillis() -
                                               lastTime)/1000.0);

        ConnectivityManager connManager = (ConnectivityManager)
                               getSystemService(CONNECTIVITY_SERVICE);
        NetworkInfo mWifi = connManager.getNetworkInfo(
                             ConnectivityManager.TYPE_WIFI);


        initialPack(data);
        initialPack(heartBeatData);
        initialPack(buttonData);
        packInt(HEART_BEAT, heartBeatData, headerLength);
        packInt(BUTTON_EVENT, buttonData, headerLength);

        if (!mPrefs.contains("ipEntry") || !mPrefs.contains("portEntry")) {
           ipInfo.setText("IP/Port Not Set.  Goto Settings and Configure");
        } else {
           ipInfo.setText("VMD Server: " + 
               mPrefs.getString("ipEntry", "") + ":" + 
               mPrefs.getString("portEntry", ""));
           startSending();
        }
        if (!(mWifi.isConnected())) {
           ipInfo.setText("WI-FI is not connected.  Please connect.");
        }

    }
    
   // ----------------------------------------------------------------
    @Override
    protected void onDestroy() {
//        Log.d(tag, "onDestroy start");
       lastTime = System.currentTimeMillis();
       stopAllSending();
       super.onDestroy();
    }    
   // ----------------------------
    @Override
    protected void onPause() {
//        Log.d(tag, "onPause start");
       lastTime = System.currentTimeMillis();
       stopAllSending();
        super.onPause();
    }    
   // -----------------------------
    @Override
    protected void onStop() {
//        Log.d(tag, "onStop start");
       lastTime = System.currentTimeMillis();
       stopAllSending();
       super.onStop();
    }    
   // ----------------------------------------------------------------
   @Override
   public boolean onCreateOptionsMenu(Menu menu){
//      logConsole("Menu has been selected");
      MenuInflater inflater = getMenuInflater();
      inflater.inflate(R.menu.menu, menu);
      return true;
   }

   // ----------------------------------------------------------------
   @Override
   public boolean onPrepareOptionsMenu(Menu menu){

      if (sendingTouch)
      {
         menu.findItem(R.id.touchPadToggle).setIcon(R.drawable.ic_menu_stop);
         menu.findItem(R.id.touchPadToggle).setTitle(R.string.sendTouchStop);
      } else {
         menu.findItem(R.id.touchPadToggle).setIcon(R.drawable.ic_menu_play_clip);
         menu.findItem(R.id.touchPadToggle).setTitle(R.string.sendTouchStart);
      }

      return super.onPrepareOptionsMenu(menu);
   }

   // ----------------------------------------------------------------
   @Override
   public boolean onOptionsItemSelected(MenuItem item) {
      // Handle item selection
      switch (item.getItemId()) {
      case R.id.settings:
         startActivity(new Intent(this, MainPreferences.class));
         return true;
      case R.id.touchPadToggle:
         if (sendingTouch)  // then we need to turn it off
         {
	    sendingTouch = false;
	 } else {           // then we need to turn it on
	    sendingTouch = true;
	 }

         // look at current state, change icon, title, actually do it
         return true;
      case R.id.resetVMDView:
         // send reset view event
	 setButtonState(31,true);
	 setButtonState(31,false);
         return true;
//      case R.id.exit:
//         logConsole("quit chosen");
//         return true;
      default:
         logConsole("item " + item.getItemId() + "chosen." 
	 );
//	 + R.id.settings + "," + R.id.exit);
         return super.onOptionsItemSelected(item);
      }
   }

   // ----------------------------------------------------------------
   // ---------------- HELPER FCTS -----------------------------------
   // ----------------------------------------------------------------
    private void packInt(final int src, byte [] dest, int offset)
    {
       dest[offset  ] = (byte)((src>>24) & 0x0ff);
       dest[offset+1] = (byte)((src>>16) & 0x0ff);
       dest[offset+2] = (byte)((src>> 8) & 0x0ff);
       dest[offset+3] = (byte)((src    ) & 0x0ff);
    }

   // ----------------------------------------------------------------
    private void packString(final String src, final int maxLen, 
                                         byte [] dest, int offset)
    {  
       // since this is getting byte-order translated, we have to 
       // tweak the ordering.  The string
       //     0123456789
       // needs to look like:
       //     32107654..98
       // (where . is null)

       // we want to only copy the first maxLen characters of the
       // string, or the entire string.. whichever one is shorter.
       int n = Math.min(maxLen, src.length()) ; 
       for(int i = 0 ; i < n ; i++) {
//          dest[offset + i] = (byte) src.charAt(i);
          dest[offset + 3-i%4 + 4* (i/4)] = (byte) src.charAt(i);
       }
       for (int i=n; n < maxLen; n++) {
          dest[offset + 3-i%4 + 4* (i/4)] = (byte) 0;
       }
    }

   // ----------------------------------------------------------------
    private void packFloat(final float src, byte [] dest, int offset)
    {
       packInt(Float.floatToRawIntBits(src), dest, offset);
    }

   // ----------------------------------------------------------------
    private void packFloatArray(float[] src, byte [] dest, int offset)
    {
       for (int i=0; i < src.length; i++)
       {
          packFloat(src[i], dest, offset+i*4);
       }
    }

   // ----------------------------------------------------------------
    // put headers in data packet that won't change
    private void initialPack(byte [] array)
    {
       // Endian check
       packInt(1, array, 0);


       // put API version at the beginning
       packInt(API_VERSION, array, 4);

       // send identifier to identify this phone.  Could be 
       // stored in a database in VMD so that VMD automatically
       // knows a user for future invocations
       packString( mPrefs.getString("nickEntry","Anonymous User"), 16, array, 8);

    } // end of initialPack

   // ----------------------------------------------------------------
    private void packAndSend(final byte [] data, final int length) 
                   throws Exception
    {
       synchronized (this) {
          if (pkt != null) {
             pkt.setData(data);
             pkt.setLength(length);
             if (skt != null && !skt.isClosed()) skt.send(pkt);
          }
       }
    }


} // end of vmdMobile class

