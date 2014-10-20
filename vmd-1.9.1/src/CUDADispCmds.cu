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
 *	$RCSfile: CUDADispCmds.cu,v $
 *	$Author: johns $	$Locker:  $		$State: Exp $
 *	$Revision: 1.4 $	$Date: 2011/12/23 23:56:19 $
 *
 ***************************************************************************
 * DESCRIPTION:
 *
 * DispCmds - different display commands which take data and put it in
 *	a storage space provided by a given VMDDisplayList object.
 *
 * Notes:
 *	1. All coordinates are stored as 3 points (x,y,z), even if meant
 * for a 2D object.  The 3rd coord for 2D objects will be ignored.
 ***************************************************************************/

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#include "Scene.h"
#include "DispCmds.h"
#include "utilities.h"
#include "Matrix4.h"
#include "VMDDisplayList.h"


//*************************************************************
// draw a mesh consisting of vertices, facets, colors, normals etc.
void DispCmdTriMesh::cuda_putdata(const float * vertices_d,
                                  const float * normals_d,
                                  const float * colors_d,
                                  int num_facets,
                                  VMDDisplayList * dobj) {
  // make a triangle mesh (no strips)
  DispCmdTriMesh *ptr;
  if (colors_d == NULL) {
    ptr = (DispCmdTriMesh *)
                (dobj->append(DTRIMESH_C3F_N3F_V3F, sizeof(DispCmdTriMesh) +
                                        sizeof(float) * num_facets * 3 * 6));
  } else {
    ptr = (DispCmdTriMesh *)
                (dobj->append(DTRIMESH_C3F_N3F_V3F, sizeof(DispCmdTriMesh) +
                                        sizeof(float) * num_facets * 3 * 9));
  }

  if (ptr == NULL)
    return;

  ptr->numverts=num_facets * 3;
  ptr->numfacets=num_facets;

  float *c=NULL, *n=NULL, *v=NULL;
  if (colors_d == NULL) {
    ptr->pervertexcolors=0;
    ptr->getpointers(n, v);
  } else {
    ptr->pervertexcolors=1;
    ptr->getpointers(c, n, v);
    cudaMemcpy(c, colors_d,   ptr->numverts * 3 * sizeof(float), cudaMemcpyDeviceToHost);
  }

  cudaMemcpy(n, normals_d,  ptr->numverts * 3 * sizeof(float), cudaMemcpyDeviceToHost);
  cudaMemcpy(v, vertices_d, ptr->numverts * 3 * sizeof(float), cudaMemcpyDeviceToHost);
}



