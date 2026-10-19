const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('danmu',{
  get:()=>ipcRenderer.invoke('get'),
  action:(name,value)=>ipcRenderer.invoke('action',name,value),
  onState:fn=>{ipcRenderer.on('state',(_,state)=>fn(state));},
  onMessage:fn=>{ipcRenderer.on('present',(_,message)=>fn(message));}
});
