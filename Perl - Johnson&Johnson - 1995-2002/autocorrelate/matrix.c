#include <stdio.h>
#include <malloc.h>
#include "matrix.h"

MATRIX mat_error( int errno )
{
   switch( errno ) {
      case MAT_MALLOC:
           fprintf(stderr, "mat: malloc error\n" );
           break;
      case MAT_FNOTOPEN:
           fprintf(stderr, "mat: fileopen error\n" );
           break;
      case MAT_FNOTGETMAT:
           fprintf(stderr, "fgetmat: matrix read error\n");
           break;
   }
   return (NULL);
}

static MATRIX  _mat_creat( int row, int col )
{
   MATBODY *mat;
   int     i, j;

   if ((mat = (MATBODY *)malloc( sizeof(MATHEAD) + sizeof(double *) * row)) == NULL)
      return (mat_error( MAT_MALLOC ));

   for (i=0; i<row; i++) {
      if ((*((double **)(&mat->matrix) + i) = (double *)malloc(sizeof(double) * col)) == NULL)
         return (mat_error( MAT_MALLOC ));
   }

   mat->head.row = row;
   mat->head.col = col;

   return (&(mat->matrix));
}

MATRIX  mat_creat( int row, int col, int type )
{
   MATRIX  A;

   if ((A =_mat_creat( row, col )) != NULL)
      return (mat_fill(A, type));
   else
      return (NULL);
}

MATRIX mat_fill( MATRIX A, int type )
{
   int i, j;

   switch (type) {
      case UNDEFINED:
           break;
      case ZERO_MATRIX:
      case UNIT_MATRIX:
           for (i=0; i<MatRow(A); i++)
              for (j=0; j<MatCol(A); j++) {
                 if (type == UNIT_MATRIX) {
                    if (i==j) 
                       A[i][j] = 1.0;
                    continue;
                 }
                 A[i][j] = 0.0;
              }
              break;
   }
   return (A);
}

int mat_free( MATRIX A )
{
   int i;

   if (A == NULL)
      return (0);
   for (i=0; i<MatRow(A); i++)
       free( A[i] );
   free( Mathead(A) );
   return (1);
}

MATRIX mat_dump( MATRIX A )
{
    return(mat_fdumpf(A, "%f ", stdout));
}

MATRIX mat_dumpf( MATRIX A, char * s )
{
    return (mat_fdumpf(A, s, stdout));
}

MATRIX mat_fdumpf( MATRIX A, char * s, FILE * fp )
{
    int i, j;

    for (i=0; i<MatRow(A); i++) {
       for (j=0; j<MatCol(A); j++) {
          fprintf( fp, s, A[i][j] );
       }
       fprintf( fp, "\n" );
    }
    return (A);
}

