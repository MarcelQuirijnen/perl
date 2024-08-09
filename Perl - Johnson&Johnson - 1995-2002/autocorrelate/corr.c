#include <stdio.h>
#include <math.h>
#include <unistd.h>
#include <string.h>
#include <limits.h>
#include "matrix.h"
#include "corr.h"

extern int errno;

/* make your life easy .. cheat */
static LINE * arr[SHRT_MAX];
static double BinList[SHRT_MAX];

/* local function prototypes */
static char * ReadLine(char *);

/* local const definitions */
#define SKIP_TILL " ELECTRIC POTENTIAL, IPT,X,Y,Z,ELPOTT\n"
static int seen = 0;

/*******/
/* Start of main program */
/*******/
int main(void)
{
   char buf[BUFSIZ];
   LINE * linepointer = NULL;
   MATRIX PropertyMatrix;
   double MaxDistance;
   int ceiling, x, y, sentinel, noofItems = 0;

   while (ReadLine(buf) != NULL) {
      linepointer = AddItem(linepointer, buf, arr);
      noofItems++;
   }
#ifdef DEBUG
   PrintList(linepointer);      
#endif

   MaxDistance = (double)0.0;
   PropertyMatrix = mat_creat(noofItems, noofItems+1, ZERO_MATRIX); 
   for (x=1; x<noofItems; x++) {
      for (y=0; y<x+1; y++) {
         PropertyMatrix[x][y] = sqrt(pow(arr[y]->x - arr[x]->x, 2) + 
                                     pow(arr[y]->y - arr[x]->y, 2) + 
                                     pow(arr[y]->z - arr[x]->z, 2));
         MaxDistance = (PropertyMatrix[x][y] > MaxDistance) ? PropertyMatrix[x][y] : MaxDistance; 
      }
   } 

#ifdef DEBUG
   printf("MaxDistance=%f\n", MaxDistance);
#endif

   sentinel = 0;
   for (x=1; x<noofItems; x++) {
      for (y=0; y<x+1; y++) {
#ifdef DEBUG
         printf("ceil = %d ", (int)ceil(PropertyMatrix[x][y]));
         printf("\nelpott * elpott = %.10f\n", arr[x]->elpott * arr[y]->elpott);
#endif
         ceiling = (int)ceil(PropertyMatrix[x][y]);
         BinList[ceiling] += (arr[x]->elpott * arr[y]->elpott); 
         sentinel = (ceiling > sentinel) ? ceiling : sentinel;
      }
   }
#ifdef DEBUG
   printf("\nSentinel = %d\n\n", sentinel);
#endif

   for (x=0; x<=sentinel; x++)
      printf("%.10f\n", BinList[x]);

#ifdef DEBUG
   mat_dumpf(PropertyMatrix, "%f "); 
#endif

   mat_free(PropertyMatrix); 
   ClearList(linepointer); 
   return(0);
}

/******/
/* Read lines from stdin
/******/
static char * ReadLine(char * buf)
{
   switch (seen) {
      case 0 : while (!seen && fgets(buf, BUFSIZ, stdin) != NULL) {
                  seen = (strcmp(SKIP_TILL, buf) == 0) ? 1 : 0; 
#ifdef DEBUG
                  if (!seen) 
                     printf("Skipping...\n");
                  else
                     printf("Ahahaha...seen.\n");
#endif
               }
               break;
      case 1 : break;
   } 
   return(fgets(buf, BUFSIZ, stdin));
}
