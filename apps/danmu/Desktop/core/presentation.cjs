'use strict';
const graphemes=text=>Array.from(new Intl.Segmenter('zh',{granularity:'grapheme'}).segment(text),x=>x.segment);
function pages(text,{width=440,font=28,lines=6}={}){
  const chars=graphemes(text);const result=[];let page='',used=0,row=1;
  // Actual wrapping is verified in the renderer with canvas measurement;
  // conservative wide-character capacity keeps emoji and Chinese readable.
  const columns=Math.max(8,Math.floor((width-40)/font));
  for(const char of chars){const unit=/^[\x20-\x7e]$/.test(char)?0.65:1;
    if(char==='\n'||used+unit>columns){row++;used=0;}
    if(row>lines){result.push(page);page='';used=0;row=1;}
    page+=char;if(char!=='\n')used+=unit;
  }
  if(page||!result.length)result.push(page);return result;
}
function duration(text,speed=4){return Math.max(12000,Math.min(45000,4000+graphemes(text).length/Math.max(2,Math.min(8,speed))*1000));}
class MessageBuffer {
  constructor(limit=500){this.limit=limit;this.queue=[];this.history=[];this.dropped=0;}
  enqueue(message){if(this.queue.length>=this.limit){this.queue.shift();this.dropped++;}this.queue.push({...message,enqueuedAt:performance.now()});this.history.unshift(message);this.history.length=Math.min(this.history.length,100);}
  clear(){this.queue=[];this.history=[];this.dropped=0;}
}
module.exports={pages,duration,MessageBuffer,graphemes};
