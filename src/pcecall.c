#include <SWI-Stream.h>
#include <SWI-Prolog.h>
#include "/staff/jan/src/pl/packages/xpce/src/h/interface.h"
#include <X11/Xlib.h>
#include <X11/Intrinsic.h>

#ifdef WIN32
#else
#define HAVE_UNISTD_H 1
#endif

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif
#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef _REENTRANT
#include <pthread.h>

static pthread_mutex_t pce_dispatch_mutex = PTHREAD_MUTEX_INITIALIZER;
#define DLOCK() pthread_mutex_lock(&pce_dispatch_mutex)
#define DUNLOCK() pthread_mutex_unlock(&pce_dispatch_mutex)
#else
#define DLOCK()
#define DUNLOCK()
#define pthread_cleanup_push(h,a)
#define pthread_cleanup_pop(e)
#endif

#ifdef HAVE_SCHED_H
#include <sched.h>
#endif

		 /*******************************
		 *	       TYPES		*
		 *******************************/

typedef struct
{ module_t module;			/* module to call in */
  record_t goal;			/* the term to call */
} prolog_goal;


typedef struct
{ int		pipe[2];
  XtInputId 	id;
} context_t;

static int init_prolog_goal(prolog_goal *g, term_t goal);
static void call_prolog_goal(prolog_goal *g);

static context_t context;


		 /*******************************
		 *	       ERRORS		*
		 *******************************/

static int
resource_error(const char *error)
{ term_t ex = PL_new_term_ref();

  PL_unify_term(ex, PL_FUNCTOR_CHARS, "error", 2,
		      PL_FUNCTOR_CHARS, "resource_error", 1,
		        PL_CHARS, error,
		      PL_VARIABLE);

  return PL_raise_exception(ex);
}

static int
type_error(term_t actual, const char *expected)
{ term_t ex = PL_new_term_ref();

  PL_unify_term(ex, PL_FUNCTOR_CHARS, "error", 2,
		      PL_FUNCTOR_CHARS, "type_error", 2,
		        PL_CHARS, expected,
		        PL_TERM, actual,
		      PL_VARIABLE);

  return PL_raise_exception(ex);
}

		 /*******************************
		 *	   X11 SCHEDULING	*
		 *******************************/

static void
on_input(XtPointer xp, int *source, XtInputId *id)
{ context_t *ctx = (context_t *)xp;
  prolog_goal g;
  int n;

  if ( (n=read(ctx->pipe[0], &g, sizeof(g))) == sizeof(g) )
  { call_prolog_goal(&g);
  } else if ( n == 0 )		/* EOF: quit */
  { close(ctx->pipe[0]);
    ctx->pipe[0] = -1;
  }
}


static int
setup()
{ if ( context.pipe[0] > 0 )
    return TRUE;

  DLOCK();
  if ( context.pipe[0] == -1 )
  { if ( pipe(context.pipe) == -1 )
    { DUNLOCK();
      return resource_error("open_files");
    }

    context.id = XtAppAddInput(pceXtAppContext(NULL),
			       context.pipe[0],
			       (XtPointer)(XtInputReadMask),
			       on_input, &context);
  }
  DUNLOCK();

  return TRUE;
}
  

static foreign_t
pl_pce_call(term_t goal)
{ prolog_goal g;
  int rc;

  if ( !setup() )
    return FALSE;

  if ( !init_prolog_goal(&g, goal) )
    return FALSE;

					/* must be locked? */
  rc = write(context.pipe[1], &g, sizeof(g));

  if ( rc == sizeof(g) )
    return TRUE;

  return FALSE;
}


		 /*******************************
		 *	CREATE/EXECUTE GOAL	*
		 *******************************/

static int
init_prolog_goal(prolog_goal *g, term_t goal)
{ term_t plain = PL_new_term_ref();

  g->module = NULL;
  PL_strip_module(goal, &g->module, plain);
  if ( !(PL_is_compound(plain) || PL_is_atom(plain)) )
    return type_error(goal, "callable");
  g->goal = PL_record(plain);

  return TRUE;
}


static void
call_prolog_goal(prolog_goal *g)
{ fid_t fid = PL_open_foreign_frame();
  term_t t = PL_new_term_ref();
  static predicate_t pred = NULL;

  if ( !pred )
    pred = PL_predicate("call", 1, "user");

  PL_recorded(g->goal, t);
  PL_erase(g->goal);
  PL_call_predicate(g->module, PL_Q_NORMAL, pred, t);
  PL_discard_foreign_frame(fid);
}


		 /*******************************
		 *	       INSTALL		*
		 *******************************/

install_t
install_pcecall()
{
#ifndef WIN32
  context.pipe[0] = context.pipe[1] = -1;
#endif

  PL_register_foreign("in_pce_thread", 1, pl_pce_call, PL_FA_TRANSPARENT);
}