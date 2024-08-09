/* datastructures */

typedef struct
{
   char * line;
   int ipt;
   double x;
   double y;
   double z;
   double elpott;
   struct LINE * next;
} LINE;


/* function prototypes */

extern LINE * AddItem (LINE *, char *, LINE **);
extern LINE * RemoveItem (LINE *);
extern void PrintList(LINE *);
extern void ClearList(LINE *);

