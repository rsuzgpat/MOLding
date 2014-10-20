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
 *	$RCSfile: CUDAQuickSurf.h,v $
 *	$Author: johns $	$Locker:  $		$State: Exp $
 *	$Revision: 1.3 $	$Date: 2011/12/05 01:29:16 $
 *
 ***************************************************************************
 * DESCRIPTION:
 *   Fast gaussian surface representation
 ***************************************************************************/
#ifndef CUDAQUICKSURF_H
#define CUDAQUICKSURF_H

class VMDDisplayList;

class CUDAQuickSurf {
  void *voidgpu; ///< pointer to structs containing private per-GPU pointers 

public:
  CUDAQuickSurf(void);

  int free_bufs(void);

  int check_bufs(long int natoms, int colorperatom, 
                 int gx, int gy, int gz);

  int alloc_bufs(long int natoms, int colorperatom, 
                 int gx, int gy, int gz);

  int get_chunk_bufs(int testexisting,
                     long int natoms, int colorperatom, 
                     int gx, int gy, int gz,
                     int &cx, int &cy, int &cz,
                     int &sx, int &sy, int &sz);

  int calc_surf(long int natoms, const float *xyzr, const float *colors,
                int colorperatom, float *origin, int* numvoxels, float maxrad,
                float radscale, float gridspacing,
                float isovalue, float gausslim,
                VMDDisplayList *cmdList);

  ~CUDAQuickSurf(void);
};

#endif

