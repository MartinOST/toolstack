#include <xlshim.h>
#include <xenvm.h>              /* Generated by dbus-gen */

int main(int argc, char *argv[]) {

  struct XenVMNotify *tmp;

  tmp = xen_vm_notify_skeleton_new();

  /* The general outline will be as follows:
   *
   * 1. XenMgr will kick us off via spawn.
   * 2. XenMgr will wait for our DBUS interface to be ready
   *  2.1 We will have to initialize our DBUS/RPC interface
   *  2.2 We have to signal XenMgr that we are ready
   * 3. We listen for any calls on our DBUS interface
   * 4. We will transform any incoming call in something that LibXL unterstands.
   * 5. Upon destroying the associated VM, we need to perform a graceful teardown.
   */

  /* Infinite loop waiting for notifications */
  while(1) {

  }

  return EXIT_SUCCESS;
}
