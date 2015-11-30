#include <stdio.h>
#include <stdlib.h>

/* As per defintion, any application that uses LibXL must define LIBXL_API_VERSION */
#ifndef LIBXL_API_VERSION
#define LIBXL_API_VERSION 0x040300 /* Xen 4.3.4 */
#endif

#include <libxl.h>

/* RPC/DBUS related stuff */

