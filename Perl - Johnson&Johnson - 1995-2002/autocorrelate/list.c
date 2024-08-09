#include <stdio.h>
#include <unistd.h>
#include "corr.h"


LINE * AddItem (LINE * linepointer, char * data, LINE * cnt[]) 
{
   LINE * lp = linepointer;
   int tmp;

   if (linepointer != NULL) {
      while (linepointer->next != NULL)
         linepointer = linepointer->next;
      linepointer->next = (struct LINE  *) malloc(sizeof(LINE));
      linepointer = linepointer->next;
      linepointer->next = NULL;
      linepointer->line = strdup(data);
      (void)sscanf(linepointer->line, "%d%lf%lf%lf%lf", &tmp, &linepointer->x, 
                                         &linepointer->y, &linepointer->z, &linepointer->elpott);
      cnt[tmp-1] = linepointer;
      linepointer->ipt = tmp;
      return lp;
   } else {
      linepointer = (struct LINE  *) malloc(sizeof(LINE));
      linepointer->next = NULL;
      linepointer->line = strdup(data);
      (void)sscanf(linepointer->line, "%d%lf%lf%lf%lf", &linepointer->ipt, &linepointer->x, 
                                         &linepointer->y, &linepointer->z, &linepointer->elpott);
      cnt[0] = linepointer;
      return linepointer;
   }
}

LINE * RemoveItem (LINE * linepointer) 
{
   LINE * tempp;
#ifdef DEBUG
   printf ("Element removed is %s\n", linepointer->line);
#endif
   tempp = linepointer->next;
   free (linepointer);
   return tempp;
}

void PrintList (LINE * linepointer) 
{
   if (linepointer == NULL)
      printf ("List is empty!\n");
   else
      while (linepointer != NULL) {
         printf ("%d\t%f\t%f\t%f\t%.10\n", linepointer->ipt, linepointer->x, linepointer->y,  
                                     linepointer->z, linepointer->elpott);
         linepointer = linepointer->next;
      }
   printf ("\n");
}

void ClearList (LINE * linepointer) 
{
   while (linepointer != NULL) {
      linepointer = RemoveItem (linepointer);
   }
}
