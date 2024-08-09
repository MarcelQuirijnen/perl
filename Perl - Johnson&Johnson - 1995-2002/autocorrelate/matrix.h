typedef struct {
        int     row;
        int     col;
} MATHEAD;

typedef struct {
        MATHEAD head;
        double  *matrix;
} MATBODY;

typedef double  **MATRIX;

#define Mathead(a)      ((MATHEAD *)((MATHEAD *)(a) - 1))
#define MatRow(a)       (Mathead(a)->row)
#define MatCol(a)       (Mathead(a)->col)

/*   mat_errors definitions */
#define MAT_MALLOC      1
#define MAT_FNOTOPEN    2
#define MAT_FNOTGETMAT  3

/*  matrice types */
#define UNDEFINED       -1
#define ZERO_MATRIX     0
#define UNIT_MATRIX     1


/* prototypes of matrix package */
MATRIX mat_error        (int);
MATRIX _mat_creat       (int, int);
MATRIX mat_creat        (int, int, int);
MATRIX mat_fill         (MATRIX, int);
int mat_free            (MATRIX);
MATRIX mat_dump         (MATRIX);
MATRIX mat_dumpf        (MATRIX, char *);
MATRIX mat_fdump        (MATRIX, FILE *);
MATRIX mat_fdumpf       (MATRIX, char *, FILE *);
