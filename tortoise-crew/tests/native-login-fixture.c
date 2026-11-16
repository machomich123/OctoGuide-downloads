
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef int (__fastcall *LuaFn)(void *);
typedef int (__fastcall *Compiler)(void *, const char *, size_t, const char *);
static LuaFn credentials_fn;
static int pushed;
static char account[32],password[32];
static int saw_lua;
static void __stdcall engine_register(void) {}
static void __fastcall add_function(const char *name,LuaFn fn) {
    if(!strcmp(name,"CrewLoginTakeCredentials")) credentials_fn=fn;
}
static void __fastcall string_push(void *vm,const char *s) {
    (void)vm;
    strcpy(pushed++ ? password : account,s);
}
static int __fastcall compile(void *vm,const char *buffer,size_t length,const char *name) {
    (void)vm; (void)name;
    const char *needle="CrewLoginTakeCredentials";
    for(size_t i=0;i+strlen(needle)<length;i++) if(!memcmp(buffer+i,needle,strlen(needle))) saw_lua=1;
    return 0;
}
static void jump(uintptr_t site, uintptr_t fn) {
    unsigned char *target=(unsigned char*)site;
    uint32_t delta=(uint32_t)(fn-site-5);
    target[0]=0xe9;
    memcpy(target+1,&delta,4);
}
static uintptr_t destination(uintptr_t site) {
    uint32_t delta;
    memcpy(&delta,(void*)(site+1),4);
    return site+5+delta;
}
static unsigned char test_section[0x930000];
int main(int argc, char **argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX);
    assert(argc==3);
    assert((uintptr_t)GetModuleHandleW(NULL)==0x00400000);
    DWORD old_flags;
    assert(VirtualProtect(test_section,sizeof(test_section),PAGE_EXECUTE_READWRITE,&old_flags));
    jump(0x0046abb0,(uintptr_t)engine_register);
    jump(0x00704120,(uintptr_t)add_function);
    jump(0x006f5690,(uintptr_t)compile);
    jump(0x006f3890,(uintptr_t)string_push);
    *(void**)0x00ceef74=(void*)123;
    memcpy((void*)0x0046a880,"\xe8\x2b\x03\x00\x00",5);
    memcpy((void*)0x00704b0c,"\xe8\x7f\x0b\xff\xff",5);
    assert(SetEnvironmentVariableA("CREW_LOGIN_CHANNEL",argv[2]));
    HMODULE mod=LoadLibraryA(argv[1]); assert(mod);
    DWORD (*load)(void)=(DWORD(*)(void))GetProcAddress(mod,"Load"); assert(load);
    assert(load()==0);
    assert(destination(0x0046a880)!=0x0046abb0);
    ((void(__stdcall*)(void))destination(0x0046a880))();
    assert(credentials_fn);
    char filename[MAX_PATH]; snprintf(filename,sizeof(filename),"%s\\credentials.bin",argv[2]);
    unsigned char cipher[4096];
    FILE *payload_file=fopen(filename,"rb"); assert(payload_file);
    size_t length=fread(cipher,1,sizeof(cipher),payload_file); fclose(payload_file);
    unsigned char extra_bytes[]="TortoiseCrew/one-shot-login/v3";
    DATA_BLOB input={(DWORD)length,cipher},extra={sizeof(extra_bytes)-1,extra_bytes},clear={0,NULL};
    assert(CryptUnprotectData(&input,NULL,&extra,NULL,NULL,CRYPTPROTECT_UI_FORBIDDEN,&clear));
    char expected[42]={0}; assert(clear.cbData<sizeof(expected)); memcpy(expected,clear.pbData,clear.cbData);
    SecureZeroMemory(clear.pbData,clear.cbData); LocalFree(clear.pbData);
    assert(credentials_fn((void*)999)==0);
    assert(credentials_fn((void*)123)==2);
    assert(pushed==2 && !strcmp(account,"MICHAEL") && strlen(password)>=1 && strlen(password)<=16);
    assert(!strcmp(strchr(expected,'\n')+1,password));
    assert(credentials_fn((void*)123)==0 && pushed==2);
    const char script[]="function AccountLogin_OnShow()\nend";
    Compiler hooked=(Compiler)destination(0x00704b0c);
    hooked((void*)999,script,sizeof(script)-1,"@Interface\\GlueXML\\AccountLogin.lua"); assert(!saw_lua);
    hooked((void*)123,script,sizeof(script)-1,"@Interface\\GlueXML\\AccountLogin.lua"); assert(saw_lua);
    puts("native hooks, correct VM, DPAPI and single consumption passed");
    return 0;
}
