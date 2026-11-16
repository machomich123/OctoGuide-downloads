#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <wincrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include "CrewLoginLua.h"

typedef int (__fastcall *LuaFunction)(void *);
typedef int (__fastcall *CompileLua)(void *, const char *, size_t, const char *);
typedef void (__fastcall *RegisterLua)(const char *, LuaFunction);
typedef void (__fastcall *PushString)(void *, const char *);
static wchar_t channel[MAX_PATH];
static void *glue_state;
static int consumed;
static const unsigned char entropy[] = "TortoiseCrew/one-shot-login/v3";

static void marker(const wchar_t *name, const char *text) {
    wchar_t path[MAX_PATH];
    swprintf(path, MAX_PATH, L"%ls\\%ls", channel, name);
    HANDLE f=CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if(f!=INVALID_HANDLE_VALUE) {
        DWORD written; WriteFile(f,text,(DWORD)strlen(text),&written,NULL); CloseHandle(f);
    }
}

static int __fastcall take_credentials(void *lua) {
    if(consumed || lua!=glue_state) return 0;
    consumed=1;
    wchar_t path[MAX_PATH];
    swprintf(path, MAX_PATH, L"%ls\\credentials.bin", channel);
    HANDLE f=CreateFileW(path, GENERIC_READ|DELETE, 0, NULL, OPEN_EXISTING, FILE_FLAG_DELETE_ON_CLOSE, NULL);
    if(f==INVALID_HANDLE_VALUE) return 0;
    unsigned char cipher[4096]; DWORD length=0;
    FILETIME created={0,0},now;
    int fresh=GetFileTime(f,&created,NULL,NULL);
    GetSystemTimeAsFileTime(&now);
    uint64_t age=(((uint64_t)now.dwHighDateTime<<32)|now.dwLowDateTime)-
                 (((uint64_t)created.dwHighDateTime<<32)|created.dwLowDateTime);
    int ok=fresh && age<UINT64_C(1200000000) && GetFileSize(f,NULL)<sizeof(cipher) &&
           ReadFile(f,cipher,sizeof(cipher),&length,NULL) && length>0;
    CloseHandle(f);
    if(!ok) return 0;
    DATA_BLOB input={length,cipher},extra={sizeof(entropy)-1,(BYTE*)entropy},plain={0,NULL};
    ok=CryptUnprotectData(&input,NULL,&extra,NULL,NULL,CRYPTPROTECT_UI_FORBIDDEN,&plain);
    SecureZeroMemory(cipher,sizeof(cipher));
    if(!ok) return 0;
    int result=0;
    // account\npassword; only printable ASCII is valid in the game protocol.
    if(plain.cbData>=3 && plain.cbData<=41) {
        char payload[42]={0}; memcpy(payload,plain.pbData,plain.cbData);
        char *separator=strchr(payload,'\n');
        if(separator) {
            *separator=0; char *password=separator+1;
            size_t n=strlen(password);
            int valid=n>=1 && n<=16 && (size_t)(separator-payload)>=2;
            for(size_t i=0;i<n;i++) if((unsigned char)password[i]<32 || (unsigned char)password[i]>126) valid=0;
            if(strcmp(payload,"MICHAEL") && strcmp(payload,"JAYKE") && strcmp(payload,"BERNARD") && strcmp(payload,"AUGUST")) valid=0;
            if(valid) {
                ((PushString)0x006f3890)(lua,payload);
                ((PushString)0x006f3890)(lua,password);
                marker(L"consumed","ok"); result=2;
            }
        }
        SecureZeroMemory(payload,sizeof(payload));
    }
    SecureZeroMemory(plain.pbData,plain.cbData); LocalFree(plain.pbData);
    return result;
}

static void __stdcall register_glue(void) {
    ((void (__stdcall *)(void))0x0046abb0)();
    glue_state=*(void**)0x00ceef74;
    ((RegisterLua)0x00704120)("CrewLoginTakeCredentials",take_credentials);
}

static int __fastcall compile_chunk(void *lua,const char *source,size_t length,const char *name) {
    const CompileLua compile=(CompileLua)0x006f5690;
    const char *file=name?strrchr(name,'\\'):NULL;
    if(!file && name) file=strrchr(name,'/');
    file=file?file+1:name; if(file && *file=='@') ++file;
    if(lua!=glue_state || !file || _stricmp(file,"AccountLogin.lua") || !length || length>262144 || source[0]=='\033' || !memchr(source,'\n',length))
        return compile(lua,source,length,name);
    size_t total=length+sizeof(crew_login_lua);
    char *combined=HeapAlloc(GetProcessHeap(),0,total);
    if(!combined) return compile(lua,source,length,name);
    memcpy(combined,source,length); combined[length]='\n';
    memcpy(combined+length+1,crew_login_lua,sizeof(crew_login_lua)-1);
    int result=compile(lua,combined,total,name); HeapFree(GetProcessHeap(),0,combined);
    if(!result) return 0;
    ((void (__fastcall *)(void*,int))0x006f3080)(lua,-2);
    return compile(lua,source,length,name);
}

static void set_call(unsigned char *site,uintptr_t target) {
    uint32_t relative=(uint32_t)(target-((uintptr_t)site+5));
    memcpy(site+1,&relative,4); FlushInstructionCache(GetCurrentProcess(),site,5);
}

__declspec(dllexport) DWORD Load(void) {
    if((uintptr_t)GetModuleHandleW(NULL)!=0x00400000) return 0;
    DWORD n=GetEnvironmentVariableW(L"CREW_LOGIN_CHANNEL",channel,MAX_PATH);
    if(!n || n>=MAX_PATH-24) return 0;
    char pid[16]; snprintf(pid,sizeof(pid),"%lu",(unsigned long)GetCurrentProcessId());
    marker(L"game.pid",pid);
    unsigned char *glue=(unsigned char*)0x0046a880,*compiler=(unsigned char*)0x00704b0c;
    if(memcmp(glue,"\xe8\x2b\x03\x00\x00",5) || memcmp(compiler,"\xe8\x7f\x0b\xff\xff",5)) {
        marker(L"unavailable","unsupported hooks"); return 0;
    }
    DWORD a,b,unused;
    if(!VirtualProtect(glue,5,PAGE_EXECUTE_READWRITE,&a)) { marker(L"unavailable","hook unavailable"); return 0; }
    if(VirtualProtect(compiler,5,PAGE_EXECUTE_READWRITE,&b)) {
        set_call(glue,(uintptr_t)register_glue); set_call(compiler,(uintptr_t)compile_chunk);
        VirtualProtect(compiler,5,b,&unused);
    } else marker(L"unavailable","compiler hook unavailable");
    VirtualProtect(glue,5,a,&unused);
    return 0;
}
#if defined(_MSC_VER) && defined(_M_IX86)
#pragma comment(linker, "/EXPORT:Load=_Load")
#endif
