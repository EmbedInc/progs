//   Program DRIVER_INSTALL
//
//   Install drivers from appropriate subdirectory of the directory this
//   program is run in.
//
//   This program should be in a directory with three subdirectories:
//   XP
//   x86
//   x64
//   These subdirectories contain the drivers for the corresponding platform
//
//   The exit values are:
//   0 - one or more drivers installed, none failed to install
//   1 - no drivers to be loaded
//   2 - unable to determine program pathname
//   3 - one or more drivers could not be loaded
//
#define WIN32_LEAN_AND_MEAN

#define _WIN32_WINNT _WIN32_WINNT_WINXP

#include <Windows.h>
#include <Setupapi.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/*****************************
**
**   Forward declared prototypes
*/
BOOL IsWow64(void);

/*****************************
**
**   Start of program DRIVER_SELECTOR.C
*/
int main (int argc, char * argv)
{
 // Locals
 OSVERSIONINFO ovi;
 BOOL is_vista_or_newer;
 BOOL is_wow64;
#define MAX_SUFFIX 4
 char path_suffix[MAX_SUFFIX];         // "XP", "x86" or "x64"
 char pathname[MAX_PATH];              // pathname of exe, becomes search template
 char basepath[MAX_PATH];              // search template minus final "*.inf"
 char fullpath[MAX_PATH];              // full path of "*.inf" file

 DWORD dw_path_len;                    // how long is it?
 DWORD i;                              // loop counter
 int nfound;                           // number of INFs detected
 int nloaded;                          // number of INFs sucessfully loaded
 WIN32_FIND_DATA fdata;                // description of one file
 HANDLE ffhandle;                      // handle for filefind operation
 BOOL morefiles;                       // more files exist
 BOOL success;                         // success flag for driver install

 // Determine the OS version we are on
 ZeroMemory(&ovi, sizeof(ovi));
 ovi.dwOSVersionInfoSize = sizeof(OSVERSIONINFO);
 GetVersionEx(&ovi);
 is_vista_or_newer = ovi.dwMajorVersion >= 6 ? TRUE : FALSE;

 // Determine if we are a Wow64 process.
 is_wow64 = IsWow64();

 // Pick the correct suffix
 if (!is_vista_or_newer)
   strncpy(path_suffix, "XP", MAX_SUFFIX);
 else if (is_wow64)
   strncpy(path_suffix, "x64", MAX_SUFFIX);
 else
   strncpy(path_suffix, "x86", MAX_SUFFIX);

 // Tell the user what we are doing
 printf("Loading drivers for %s.\n", path_suffix);

 // Build the relative pathname
 dw_path_len = GetModuleFileName(NULL, pathname, MAX_PATH);
 if (dw_path_len == 0)
 {
   printf("Unable to determine program pathname.\n");
   exit(3);
 }

 // walk backward thru the pathname looking for the last
 // backslash character
 for (i = dw_path_len; i > 0; --i)
 {
   if (pathname[i-1] == '\\')
     break;
 }

 // i is now the index of the first character following the
 // last '\' in the pathname

 // tack on the search template suffix
 pathname[i] = 0;
 strncat(pathname, path_suffix, MAX_PATH);
 strncat(pathname, "\\", MAX_PATH);
 strncpy(basepath, pathname, MAX_PATH);
 strncat(pathname, "*.inf", MAX_PATH);

 // get ready to loop through all the .INF files
 nfound = 0;
 nloaded = 0;
 ZeroMemory(&fdata, sizeof(fdata));
 ffhandle = FindFirstFile(pathname, &fdata);

 // if FindFirstFile failed then we have no drivers to load
 if (ffhandle == INVALID_HANDLE_VALUE)
 {
   printf("No drivers to be loaded.\n");
   exit(0);
 }

 // loop until we process all the files
 morefiles = TRUE;
 while (morefiles)
 {
   ++nfound;

   // build the full pathname
   strncpy(fullpath, basepath, MAX_PATH);
   strncat(fullpath, fdata.cFileName, MAX_PATH);

     // report on what we are trying to do
   printf("Loading %s...", fullpath);


   // do the load
   success = SetupCopyOEMInf (
       fullpath,
     NULL,                             //no media pathname supplied
     SPOST_PATH,                       //use the INF file pathname
     0,                                //no special copy flags
     NULL, 0,                          //don't need saved pathname
     NULL,                             //don't need length of saved pathname
     NULL                              //don't need leaf name position
   );

   // report on results
   if (success)
   {
     ++nloaded;
     printf(" success.\n");
   }
   else
   {
     printf(" failed, error code = 0x%X.\n", GetLastError());
   }

   // get the next file to be processed, if any
   morefiles = FindNextFile(ffhandle, &fdata);
 }

 // clean up the find operation
 FindClose(ffhandle);

 // report what we did based on the values of
 // nfound and nloaded
 if (nloaded == 1)
   printf("Installed 1 driver.\n");
 else
   printf("Installed %d drivers.\n", nloaded);

 // complain if we had some we could not load
 if (nloaded != nfound)
 {
   if (nfound-nloaded == 1)
     printf("Unable to install 1 driver.\n");
   else
     printf("Unable to install %d drivers.\n", nfound-nloaded);
   exit(3);                            // report failure to load them all
 }

 // success
 exit(0);
}

/*****************************
**
**   Determine if we are 32-bit code
**   running on a 64-bit Windows
*/

/* NOTE: The "IsWow64Process" API isn't even available
**       in early versionsof XP. To avoid crashing on
**    program load we have to try to dynamically get the
**      address of the function from KERNEL.DLL.
*/

BOOL IsWow64(void)
{
 // Declare a type which is the type of the function we are
 // looking for
 typedef BOOL (WINAPI *LPFN_ISWOW64PROCESS) (HANDLE, PBOOL);

 // The handle to the kernel32 dll
 HMODULE hKernel = NULL;

 // The pointer to the function, if it exists
 LPFN_ISWOW64PROCESS fnIsWow64Process = NULL;

 // The retrieved flag
 BOOL is_wow64;

 // Get the handle of the DLL that contains our function
 hKernel = GetModuleHandle("kernel32");
 if (hKernel == NULL)                  // this should never happen, but..
   return FALSE;                       // ...assume we are not on 64-bit

 // Get the pointer to the function itself, if we can
    fnIsWow64Process =
   (LPFN_ISWOW64PROCESS) GetProcAddress(hKernel, "IsWow64Process");
 if (fnIsWow64Process == NULL)         // if the function doesn't exits...
   return FALSE;                       // we are definititely not on 64-bit

 // Call the function. If the call fails assume we are not Wow-64
 if (!fnIsWow64Process(GetCurrentProcess(), &is_wow64))
   return FALSE;

 // Return the value the we got
    return is_wow64;
}
