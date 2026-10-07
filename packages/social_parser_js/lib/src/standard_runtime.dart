/// JS networking policy over FJS fetch; Dart is only the optional transport seam.
const standardRuntimeModule = r'''
const nativeFetch = globalThis.fetch;
// LLRT 89941ae validates these init fields but its getters return defaults.
// Retain them in JS so fetch(new Request(...)) has the same policy as fetch(url, init).
const BuiltinRequest = globalThis.Request;
globalThis.Request = class Request extends BuiltinRequest {
  constructor(input, init={}) {
    super(input, init);
    Object.defineProperty(this, 'credentials', {value:init.credentials??input?.credentials??'same-origin'});
    Object.defineProperty(this, 'redirect', {value:init.redirect??input?.redirect??'follow'});
    if(init.signal)Object.defineProperty(this, 'signal', {value:init.signal});
  }
};
let config = null;
const error = (code,message) => Object.assign(new Error(message),{code});
export function configure(value) { config = value; }
Object.defineProperty(globalThis, 'parserContext', {get() {
  if(!config)throw error('permissionDenied','Task context is unavailable during validation');
  return Object.freeze({cookies:Object.freeze({...config.cookies}),headers:Object.freeze({...config.headers}),timeoutMs:Math.max(0,config.deadline-Date.now())});
}});
async function cacheCall(method,args) {
  if(!config)throw error('permissionDenied','Cache is unavailable during validation');
  const result=await fjs.bridge_call({method,args});
  if(!result.ok)throw error(result.code,result.message);
  return result.value;
}
Object.defineProperty(globalThis,'parserCache',{value:Object.freeze({
  get:key=>cacheCall('cache.get',{key}),
  set:(key,value,ttlMs=3600000)=>cacheCall('cache.set',{key,value,ttlMs})
})});
const allowed = (url,domains) => ['http:','https:'].includes(url.protocol)&&!url.username&&!url.password&&domains.some(d=>url.hostname===d||url.hostname.endsWith('.'+d));
async function bridge(args) {
  const result = await fjs.bridge_call({method:'fetch',args});
  if(!result.ok) throw error(result.code,result.message);
  const value=result.value, headers=new Headers();
  for(const [key,values] of Object.entries(value.headers)) for(const v of values) headers.append(key,v);
  const response=new Response([204,205,304].includes(value.status)?null:value.body,{status:value.status,headers});
  Object.defineProperty(response,'url',{value:value.url});
  return response;
}
globalThis.fetch = async function(input, init={}) {
  if(!config) throw error('permissionDenied','Fetch disabled during validation');
  const request=new Request(input,init);
  let url=new URL(request.url), method=request.method;
  let body=['GET','HEAD'].includes(method)?undefined:await request.text();
  let headers=new Headers(config.headers);
  for(const [key,value] of request.headers.entries())headers.set(key,value);
  if(!headers.has('user-agent'))headers.set('user-agent',config.userAgent);
  let credentials=(init.credentials??request.credentials)!=='omit';
  const redirect=init.redirect??request.redirect;
  const signal=init.signal??request.signal;
  let callerAborted=false;
  const controller=new AbortController();
  const abort=()=>{callerAborted=true;controller.abort(signal?.reason);};
  if(signal?.aborted)abort();
  signal?.addEventListener('abort',abort,{once:true});
  const timer=setTimeout(()=>controller.abort(error('timeout','Request timed out')),Math.max(1,config.deadline-Date.now()));
  try {
    for(let i=0;i<9;i++) {
      if(!allowed(url,config.requestDomains))throw error('permissionDenied','Request domain is not allowed');
      const sent=new Headers(headers);
      if(!credentials||!allowed(url,config.cookieDomains)){sent.delete('cookie');sent.delete('authorization');}
      else if(!sent.has('cookie')&&Object.keys(config.cookies).length)sent.set('cookie',Object.entries(config.cookies).map(([k,v])=>`${k}=${v}`).join('; '));
      const response=config.nativeTransport
        ? await nativeFetch(url.href,{method,headers:sent,body,redirect:'manual',signal:controller.signal})
        : await bridge({url:url.href,method,headers:Object.fromEntries(sent.entries()),body});
      if(controller.signal.aborted)throw controller.signal.reason;
      if(!allowed(new URL(response.url||url.href),config.requestDomains))throw error('permissionDenied','Response domain is not allowed');
      const location=response.headers.get('location');
      if([301,302,303,307,308].includes(response.status)&&redirect!=='manual'&&location){
        await response.body?.cancel();
        if(redirect==='error')throw error('network','Unexpected redirect');
        const next=new URL(location,url);
        if(next.origin!==url.origin){credentials=false;headers=new Headers({'user-agent':sent.get('user-agent')});}
        if(response.status===303||([301,302].includes(response.status)&&method==='POST')){method='GET';body=undefined;headers.delete('content-type');headers.delete('content-length');}
        url=next;continue;
      }
      const chunks=[];let size=0;
      if(response.body){const reader=response.body.getReader();try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>16*1024*1024){await reader.cancel();throw error('parseFailed','Response exceeds 16 MiB');}chunks.push(value);}}finally{reader.releaseLock();}}
      const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
      const result=new Response([204,205,304].includes(response.status)||method==='HEAD'?null:bytes,{status:response.status,statusText:response.statusText,headers:response.headers});
      Object.defineProperty(result,'url',{value:response.url||url.href});
      Object.defineProperty(result,'redirected',{value:i>0});
      return result;
    }
    throw error('network','Too many redirects');
  } catch(e) {
    if(controller.signal.aborted)throw error(callerAborted?'cancelled':'timeout','Request aborted');
    if(typeof e?.code==='string')throw e;
    throw error('network','HTTP request failed');
  } finally {clearTimeout(timer);signal?.removeEventListener('abort',abort);}
};
''';
