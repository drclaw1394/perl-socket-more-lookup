#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "const-c.inc"


#ifdef WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <sys/un.h>
#endif

MODULE = Socket::More::Lookup		PACKAGE = Socket::More::Lookup		

INCLUDE: const-xs.inc


BOOT:
#ifdef WIN32
     // Initialize Winsock or nothing works
     WSADATA wsaData;
     int iResult;
      iResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
      if (iResult != 0) {
          Perl_croak(aTHX_ "WSAStartup failed: %d\n", iResult);
      }
#endif

SV*
getaddrinfo(hostname, servicename, hints, results)
    SV *hostname
    SV *servicename
    SV *hints
    AV *results

  PROTOTYPE: $$$\@

  INIT:
    int ret;
    char *hname=NULL;
    char *sname=NULL;
    struct addrinfo *res;
    struct addrinfo h;
    struct addrinfo *next;
    int len;
    SV *temp;
    

  PPCODE: 

    h.ai_flags=0;
    h.ai_family=0;
    h.ai_socktype=0;
    h.ai_protocol=0;
    h.ai_addrlen=0;
    h.ai_addr=NULL;
    h.ai_canonname=NULL;
    h.ai_next=NULL;

    // First check that output array is doable
    
    //expectiong a hostname 

    if(SvOK(hostname) && SvPOK(hostname)){
      len=SvCUR(hostname);
      hname=SvPVX(hostname);//SvGROW(hostname,1);
      hname[len]='\0';
      //Perl_croak(aTHX_ "This croaked because: %" SVf "\n", SVfARG(hostname));
    }
    else{
    }
    if(SvOK(servicename)){
      if(SvPOK(servicename)){
        len=SvCUR(servicename);
        sname=SvPVX(servicename);//SvGROW(servicename,1);
        sname[len]='\0';
      }
      else if (SvIOK(servicename)){
        temp=newSVpvf("%" SVf , SVfARG(servicename));
        len=SvCUR(temp);
        sname=SvPVX(temp);
        sname[len]='\0';
      }


    }

    if(SvOK(hints) && SvROK(hints)){
      SV** temp;
      HV* hv=(HV *)SvRV(hints);

      temp=hv_fetch(hv,"flags",5,1);
      if((temp != NULL ) &&SvIOK(*temp)){

        h.ai_flags = SvIV(*temp);
      }
      temp=hv_fetch(hv,"family",6,1);
      if((temp != NULL ) &&SvIOK(*temp)){
        h.ai_family = SvIV(*temp);
      }
      temp=hv_fetch(hv,"type",4,1);
      if((temp != NULL ) &&SvIOK(*temp)){
        h.ai_socktype = SvIV(*temp);
      }
      temp=hv_fetch(hv,"protocol",8,1);
      if((temp != NULL ) &&SvIOK(*temp)){
        h.ai_protocol = SvIV(*temp);
      }
    }

    //XSRETURN_UNDEF;

    ret=getaddrinfo(hname, sname, &h, &res);


    if(ret!=0){
      // The return array to error?
      errno=ret;
      //SV * e=get_sv("!",GV_ADD);
      //sv_setiv(e, ret);
      //sv_setpv(e, gai_strerror(ret));
      XSRETURN_UNDEF;
    }
    else{
      // Copy results into output array
      HV *h;
      int count=0;
      next=res;
      while(next){
        count++;
        next=next->ai_next;
      }
      av_extend(results,count);
      //Resize output array to  fit count 
      int i=0;
      next=res;
      while(next){
        h=newHV();
        hv_store(h, "family", 6, newSViv(next->ai_family), 0);
        hv_store(h, "type", 4, newSViv(next->ai_socktype), 0);
        hv_store(h, "protocol", 8, newSViv(next->ai_protocol), 0);
        hv_store(h, "addr", 4, newSVpv((char *)(next->ai_addr), next->ai_addrlen), 0);
        hv_store(h, "canonname", 9, newSVpv(next->ai_canonname,0), 0);

        //Push results to return stack
        next=next->ai_next;
        av_store(results,i,newRV((SV *)h));
        i++;
        //mXPUSHs(newRV((SV *)h));
        //count++;

      }
      freeaddrinfo(res);





      XSRETURN_IV(1);
    }

const char *
gai_strerror(code)
  int code;


SV*
getnameinfo(address, IN_OUT hostname, IN_OUT servicename, flags)
    SV *address
    SV *hostname
    SV *servicename
    SV *flags

  PROTOTYPE: $$$$
  
  INIT:
    int ret;
    char *host;
    char *service;
    int fl;
    int addrlen;
    struct sockaddr *addr;

  PPCODE:

    //Ensure outputs are not readonly
    
    if(SvREADONLY(hostname) || SvREADONLY(servicename)){
            Perl_croak(aTHX_ "%s", PL_no_modify);
    }

    if(SvOK(address) && SvPOK(address)){
      addrlen=SvCUR(address);
      addr=(struct sockaddr *)SvPVX(address);//SvGROW(address,0);
    }

    if(!SvOK(hostname)){
      hostname=sv_2mortal(newSV(NI_MAXHOST+1));

    }

    SvPOK_on(hostname);
    host=SvGROW(hostname, NI_MAXHOST+1);

    if(!SvOK(servicename)){
      servicename=sv_2mortal(newSV(NI_MAXSERV+1));
    }

    SvPOK_on(servicename);
    service=SvGROW(servicename, NI_MAXSERV+1);


    if(SvOK(flags)  && SvIOK(flags)){
      fl=SvIV(flags); 
    }
    else {
      fl=0;
    }
    
    ret=getnameinfo(addr, addrlen, host, NI_MAXHOST, service, NI_MAXSERV, fl);

    if(ret==0){
      //Update the actual length used
      SvCUR_set(hostname, strlen(host));
      SvCUR_set(servicename, strlen(service));

      //Return as no error (true)
      XSRETURN_IV(1);

    }
    else {
      //return as error, and set errno
      errno=ret;
      //SV * e=get_sv("!",GV_ADD);
      //sv_setiv(e, ret);
      //sv_setpv(e, gai_strerror(ret));
      XSRETURN_UNDEF; 
    }

