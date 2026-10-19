(function(root){
 'use strict';
 const defaults=Object.freeze({version:1,name:'中台默认',background:null,foreground:null,border:null,fontSize:28,corner:12,layout:'split',showHistory:true,motion:'scroll'});
 function luminance(hex){const c=hex.slice(1).match(/../g).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return .2126*c[0]+.7152*c[1]+.0722*c[2];}
 function validate(input){
  if(!input||typeof input!=='object'||Array.isArray(input))throw new Error('请粘贴一个外观 JSON 对象');
  for(const key of Object.keys(input))if(!Object.hasOwn(defaults,key))throw new Error('不支持的配置项：'+key+'。这里只能修改外观');
  const a={...defaults,...input};
  if(a.version!==1||typeof a.name!=='string'||!a.name.trim()||a.name.length>40)throw new Error('外观名称须为 1 至 40 个字，版本须为 1');
  for(const k of ['background','foreground','border'])if(a[k]!==null&&(typeof a[k]!=='string'||!/^#[0-9a-f]{6}$/i.test(a[k])))throw new Error('颜色须为六位十六进制色值或 null');
  if((a.background===null)!==(a.foreground===null))throw new Error('背景色和文字色需要一起设置或一起恢复默认');
  if(a.background&&a.foreground){const x=luminance(a.background),y=luminance(a.foreground);if((Math.max(x,y)+.05)/(Math.min(x,y)+.05)<4.5)throw new Error('文字与背景对比度过低，请让 Agent 调整为至少 4.5∶1');}
  if(!Number.isInteger(a.fontSize)||a.fontSize<22||a.fontSize>44||!Number.isInteger(a.corner)||a.corner<0||a.corner>24)throw new Error('字号须为 22 至 44，圆角须为 0 至 24 的整数');
  if(!['split','reading'].includes(a.layout)||typeof a.showHistory!=='boolean'||!['scroll','static'].includes(a.motion))throw new Error('布局、历史显示或动效选项无效');
  return a;
 }
 const api={defaults,validate};if(typeof module==='object'&&module.exports)module.exports=api;else root.DanmuAppearance=api;
})(globalThis);
