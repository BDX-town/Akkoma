(window.webpackJsonp=window.webpackJsonp||[]).push([[4],{1065:function(t,e,n){"use strict";n.r(e);n(864),n(865);var i=n(866);n.n(i)()()},864:function(t,e){!function(){"use strict";var y,n,_,I;function s(t){try{return t.defaultView&&t.defaultView.frameElement||null}catch(t){return null}}function a(t){this.time=t.time,this.target=t.target,this.rootBounds=l(t.rootBounds),this.boundingClientRect=l(t.boundingClientRect),this.intersectionRect=l(t.intersectionRect||r()),this.isIntersecting=!!t.intersectionRect;var e=this.boundingClientRect,n=e.width*e.height,i=this.intersectionRect,o=i.width*i.height;this.intersectionRatio=n?Number((o/n).toFixed(4)):this.isIntersecting?1:0}function t(t,e){var n,i,o,r=e||{};if("function"!=typeof t)throw new Error("callback must be a function");if(r.root&&1!=r.root.nodeType)throw new Error("root must be an Element");this._checkForIntersections=(n=this._checkForIntersections.bind(this),i=this.THROTTLE_TIMEOUT,o=null,function(){o=o||setTimeout(function(){n(),o=null},i)}),this._callback=t,this._observationTargets=[],this._queuedEntries=[],this._rootMarginValues=this._parseRootMargin(r.rootMargin),this.thresholds=this._initThresholds(r.threshold),this.root=r.root||null,this.rootMargin=this._rootMarginValues.map(function(t){return t.value+t.unit}).join(" "),this._monitoringDocuments=[],this._monitoringUnsubscribes=[]}function c(t,e,n,i){"function"==typeof t.addEventListener?t.addEventListener(e,n,i||!1):"function"==typeof t.attachEvent&&t.attachEvent("on"+e,n)}function u(t,e,n,i){"function"==typeof t.removeEventListener?t.removeEventListener(e,n,i||!1):"function"==typeof t.detatchEvent&&t.detatchEvent("on"+e,n)}function T(t){var e;try{e=t.getBoundingClientRect()}catch(t){}return e?(e.width&&e.height||(e={top:e.top,right:e.right,bottom:e.bottom,left:e.left,width:e.right-e.left,height:e.bottom-e.top}),e):r()}function r(){return{top:0,bottom:0,left:0,right:0,width:0,height:0}}function l(t){return!t||"x"in t?t:{top:t.top,y:t.top,bottom:t.bottom,left:t.left,x:t.left,right:t.right,width:t.width,height:t.height}}function E(t,e){var n=e.top-t.top,i=e.left-t.left;return{top:n,left:i,height:e.height,width:e.width,bottom:n+e.height,right:i+e.width}}function e(t,e){for(var n=e;n;){if(n==t)return!0;n=R(n)}return!1}function R(t){var e=t.parentNode;return 9==t.nodeType&&t!=y?s(t):e&&11==e.nodeType&&e.host?e.host:e&&e.assignedSlot?e.assignedSlot.parentNode:e}"object"==typeof window&&("IntersectionObserver"in window&&"IntersectionObserverEntry"in window&&"intersectionRatio"in window.IntersectionObserverEntry.prototype?"isIntersecting"in window.IntersectionObserverEntry.prototype||Object.defineProperty(window.IntersectionObserverEntry.prototype,"isIntersecting",{get:function(){return 0<this.intersectionRatio}}):(y=function(){for(var t=window.document,e=s(t);e;)e=s(t=e.ownerDocument);return t}(),n=[],I=_=null,t.prototype.THROTTLE_TIMEOUT=100,t.prototype.POLL_INTERVAL=null,t.prototype.USE_MUTATION_OBSERVER=!0,t._setupCrossOriginUpdater=function(){return _=_||function(t,e){I=t&&e?E(t,e):r(),n.forEach(function(t){t._checkForIntersections()})}},t._resetCrossOriginUpdater=function(){I=_=null},t.prototype.observe=function(e){if(!this._observationTargets.some(function(t){return t.element==e})){if(!e||1!=e.nodeType)throw new Error("target must be an Element");this._registerInstance(),this._observationTargets.push({element:e,entry:null}),this._monitorIntersections(e.ownerDocument),this._checkForIntersections()}},t.prototype.unobserve=function(e){this._observationTargets=this._observationTargets.filter(function(t){return t.element!=e}),this._unmonitorIntersections(e.ownerDocument),0==this._observationTargets.length&&this._unregisterInstance()},t.prototype.disconnect=function(){this._observationTargets=[],this._unmonitorAllIntersections(),this._unregisterInstance()},t.prototype.takeRecords=function(){var t=this._queuedEntries.slice();return this._queuedEntries=[],t},t.prototype._initThresholds=function(t){var e=t||[0];return Array.isArray(e)||(e=[e]),e.sort().filter(function(t,e,n){if("number"!=typeof t||isNaN(t)||t<0||1<t)throw new Error("threshold must be a number between 0 and 1 inclusively");return t!==n[e-1]})},t.prototype._parseRootMargin=function(t){var e=(t||"0px").split(/\s+/).map(function(t){var e=/^(-?\d*\.?\d+)(px|%)$/.exec(t);if(!e)throw new Error("rootMargin must be specified in pixels or percent");return{value:parseFloat(e[1]),unit:e[2]}});return e[1]=e[1]||e[0],e[2]=e[2]||e[0],e[3]=e[3]||e[1],e},t.prototype._monitorIntersections=function(e){var n,i,o,t,r=e.defaultView;r&&-1==this._monitoringDocuments.indexOf(e)&&(n=this._checkForIntersections,o=i=null,this.POLL_INTERVAL?i=r.setInterval(n,this.POLL_INTERVAL):(c(r,"resize",n,!0),c(e,"scroll",n,!0),this.USE_MUTATION_OBSERVER&&"MutationObserver"in r&&(o=new r.MutationObserver(n)).observe(e,{attributes:!0,childList:!0,characterData:!0,subtree:!0})),this._monitoringDocuments.push(e),this._monitoringUnsubscribes.push(function(){var t=e.defaultView;t&&(i&&t.clearInterval(i),u(t,"resize",n,!0)),u(e,"scroll",n,!0),o&&o.disconnect()}),e==(this.root&&this.root.ownerDocument||y)||(t=s(e))&&this._monitorIntersections(t.ownerDocument))},t.prototype._unmonitorIntersections=function(i){var o,t,e,n=this._monitoringDocuments.indexOf(i);-1!=n&&(o=this.root&&this.root.ownerDocument||y,this._observationTargets.some(function(t){if((e=t.element.ownerDocument)==i)return!0;for(;e&&e!=o;){var e,n=s(e);if((e=n&&n.ownerDocument)==i)return!0}return!1})||(t=this._monitoringUnsubscribes[n],this._monitoringDocuments.splice(n,1),this._monitoringUnsubscribes.splice(n,1),t(),i==o||(e=s(i))&&this._unmonitorIntersections(e.ownerDocument)))},t.prototype._unmonitorAllIntersections=function(){var t=this._monitoringUnsubscribes.slice(0);this._monitoringDocuments.length=0;for(var e=this._monitoringUnsubscribes.length=0;e<t.length;e++)t[e]()},t.prototype._checkForIntersections=function(){var c,u;!this.root&&_&&!I||(c=this._rootIsInDom(),u=c?this._getRootRect():r(),this._observationTargets.forEach(function(t){var e=t.element,n=T(e),i=this._rootContainsTarget(e),o=t.entry,r=c&&i&&this._computeTargetAndRootIntersection(e,n,u),s=t.entry=new a({time:window.performance&&performance.now&&performance.now(),target:e,boundingClientRect:n,rootBounds:_&&!this.root?null:u,intersectionRect:r});o?c&&i?this._hasCrossedThreshold(o,s)&&this._queuedEntries.push(s):o&&o.isIntersecting&&this._queuedEntries.push(s):this._queuedEntries.push(s)},this),this._queuedEntries.length&&this._callback(this.takeRecords(),this))},t.prototype._computeTargetAndRootIntersection=function(t,e,n){if("none"!=window.getComputedStyle(t).display){for(var i,o,r,s,c,u,a,l,h=e,f=R(t),d=!1;!d&&f;){var g,p,m,b,w=null,v=1==f.nodeType?window.getComputedStyle(f):{};if("none"==v.display)return null;if(f==this.root||9==f.nodeType?(d=!0,f==this.root||f==y?_&&!this.root?!I||0==I.width&&0==I.height?h=w=f=null:w=I:w=n:(p=(g=R(f))&&T(g),m=g&&this._computeTargetAndRootIntersection(g,p,n),p&&m?(f=g,w=E(p,m)):h=f=null)):f!=(b=f.ownerDocument).body&&f!=b.documentElement&&"visible"!=v.overflow&&(w=T(f)),w&&(i=w,o=h,l=a=u=c=s=r=void 0,r=Math.max(i.top,o.top),s=Math.min(i.bottom,o.bottom),c=Math.max(i.left,o.left),u=Math.min(i.right,o.right),l=s-r,h=0<=(a=u-c)&&0<=l?{top:r,bottom:s,left:c,right:u,width:a,height:l}:null),!h)break;f=f&&R(f)}return h}},t.prototype._getRootRect=function(){var t,e,n;return n=this.root?T(this.root):(t=y.documentElement,e=y.body,{top:0,left:0,right:t.clientWidth||e.clientWidth,width:t.clientWidth||e.clientWidth,bottom:t.clientHeight||e.clientHeight,height:t.clientHeight||e.clientHeight}),this._expandRectByRootMargin(n)},t.prototype._expandRectByRootMargin=function(n){var t=this._rootMarginValues.map(function(t,e){return"px"==t.unit?t.value:t.value*(e%2?n.width:n.height)/100}),e={top:n.top-t[0],right:n.right+t[1],bottom:n.bottom+t[2],left:n.left-t[3]};return e.width=e.right-e.left,e.height=e.bottom-e.top,e},t.prototype._hasCrossedThreshold=function(t,e){var n=t&&t.isIntersecting?t.intersectionRatio||0:-1,i=e.isIntersecting?e.intersectionRatio||0:-1;if(n!==i)for(var o=0;o<this.thresholds.length;o++){var r=this.thresholds[o];if(r==n||r==i||r<n!=r<i)return!0}},t.prototype._rootIsInDom=function(){return!this.root||e(y,this.root)},t.prototype._rootContainsTarget=function(t){return e(this.root||y,t)&&(!this.root||this.root.ownerDocument==t.ownerDocument)},t.prototype._registerInstance=function(){n.indexOf(this)<0&&n.push(this)},t.prototype._unregisterInstance=function(){var t=n.indexOf(this);-1!=t&&n.splice(t,1)},window.IntersectionObserver=t,window.IntersectionObserverEntry=a))}()},865:function(i,o,t){(function(O){var t,e,n;e=[],void 0===(n="function"==typeof(t=function(){"use strict";var o,r,s,t,i=typeof window!="undefined"?window:typeof O!=undefined?O:this||{},e=i.cancelRequestAnimationFrame&&i.requestAnimationFrame||setTimeout,n=i.cancelRequestAnimationFrame||clearTimeout,c=[],u=0,a=false,l=7,h=35,f=125,d=0,g=0,p=0,m={get didTimeout(){return false},timeRemaining:function t(){var t=l-(Date.now()-g);return t<0?0:t}},b=w(function(){l=22;f=66;h=0});function w(n){var i,o;var r=99;var t=function t(){var e=Date.now()-o;if(e<r){i=setTimeout(t,r-e)}else{i=null;n()}};return function(){o=Date.now();if(!i){i=setTimeout(t,r)}}}function v(){if(a){if(t){n(t)}if(s){clearTimeout(s)}a=false}}function y(){if(f!=125){l=7;f=125;h=35;if(a){v();T()}}b()}function _(){t=null;s=setTimeout(E,0)}function I(){s=null;e(_)}function T(){if(a){return}r=f-(Date.now()-g);o=Date.now();a=true;if(h&&r<h){r=h}if(r>9){s=setTimeout(I,r)}else{r=0;I()}}function E(){var t,e,n;var i=l>9?9:1;g=Date.now();a=false;s=null;if(u>2||g-r-50<o){for(e=0,n=c.length;e<n&&m.timeRemaining()>i;e++){t=c.shift();p++;if(t){t(m)}}}if(c.length){T()}else{u=0}}function R(t){d++;c.push(t);T();return d}function k(t){var e=t-1-p;if(c[e]){c[e]=null}}if(!i.requestIdleCallback||!i.cancelIdleCallback){i.requestIdleCallback=R;i.cancelIdleCallback=k;if(i.document&&document.addEventListener){i.addEventListener("scroll",y,true);i.addEventListener("resize",y);document.addEventListener("focus",y,true);document.addEventListener("mouseover",y,true);["click","keypress","touchstart","mousedown"].forEach(function(t){document.addEventListener(t,y,{capture:true,passive:true})});if(i.MutationObserver){new MutationObserver(y).observe(document.documentElement,{childList:true,subtree:true,attributes:true})}}}else{try{i.requestIdleCallback(function(){},{timeout:0})}catch(t){(function(n){var t,e;i.requestIdleCallback=function(t,e){if(e&&typeof e.timeout=="number"){return n(t,e.timeout)}return n(t)};if(i.IdleCallbackDeadline&&(t=IdleCallbackDeadline.prototype)){e=Object.getOwnPropertyDescriptor(t,"timeRemaining");if(!e||!e.configurable||!e.get){return}Object.defineProperty(t,"timeRemaining",{value:function t(){return e.get.call(this)},enumerable:true,configurable:true})}})(i.requestIdleCallback)}}return{request:R,cancel:k}})?t.apply(o,e):t)||(i.exports=n)}).call(this,t(121))},866:function(t,e,n){"use strict";var c="bfred-it:object-fit-images",u=/(object-fit|object-position)\s*:\s*([-.\w\s%]+)/g,i="undefined"==typeof Image?{style:{"object-position":1}}:new Image,a="object-fit"in i.style,o="object-position"in i.style,r="background-size"in i.style,l="string"==typeof i.currentSrc,h=i.getAttribute,f=i.setAttribute,s=!1;function d(t,e,n){var i="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='"+(e||1)+"' height='"+(n||0)+"'%3E%3C/svg%3E";h.call(t,"src")!==i&&f.call(t,"src",i)}function g(t,e){t.naturalWidth?e(t):setTimeout(g,100,t,e)}function p(e){var n,i,t,o,r=function(t){for(var e,n=getComputedStyle(t).fontFamily,i={};null!==(e=u.exec(n));)i[e[1]]=e[2];return i}(e),s=e[c];if(r["object-fit"]=r["object-fit"]||"fill",!s.img){if("fill"===r["object-fit"])return;if(!s.skipTest&&a&&!r["object-position"])return}if(!s.img){s.img=new Image(e.width,e.height),s.img.srcset=h.call(e,"data-ofi-srcset")||e.srcset,s.img.src=h.call(e,"data-ofi-src")||e.src,f.call(e,"data-ofi-src",e.src),e.srcset&&f.call(e,"data-ofi-srcset",e.srcset),d(e,e.naturalWidth||e.width,e.naturalHeight||e.height),e.srcset&&(e.srcset="");try{n=e,i={get:function(t){return n[c].img[t||"src"]},set:function(t,e){return n[c].img[e||"src"]=t,f.call(n,"data-ofi-"+e,t),p(n),t}},Object.defineProperty(n,"src",i),Object.defineProperty(n,"currentSrc",{get:function(){return i.get("currentSrc")}}),Object.defineProperty(n,"srcset",{get:function(){return i.get("srcset")},set:function(t){return i.set(t,"srcset")}})}catch(t){window.console&&console.warn("https://bit.ly/ofi-old-browser")}}(t=s.img).srcset&&!l&&window.picturefill&&(t[(o=window.picturefill._).ns]&&t[o.ns].evaled||o.fillImg(t,{reselect:!0}),t[o.ns].curSrc||(t[o.ns].supported=!1,o.fillImg(t,{reselect:!0})),t.currentSrc=t[o.ns].curSrc||t.src),e.style.backgroundImage='url("'+(s.img.currentSrc||s.img.src).replace(/"/g,'\\"')+'")',e.style.backgroundPosition=r["object-position"]||"center",e.style.backgroundRepeat="no-repeat",e.style.backgroundOrigin="content-box",/scale-down/.test(r["object-fit"])?g(s.img,function(){s.img.naturalWidth>e.width||s.img.naturalHeight>e.height?e.style.backgroundSize="contain":e.style.backgroundSize="auto"}):e.style.backgroundSize=r["object-fit"].replace("none","auto").replace("fill","100% 100%"),g(s.img,function(t){d(e,t.naturalWidth,t.naturalHeight)})}function m(t,e){var n=!s&&!t;if(e=e||{},t=t||"img",o&&!e.skipTest||!r)return!1;"img"===t?t=document.getElementsByTagName("img"):"string"==typeof t?t=document.querySelectorAll(t):"length"in t||(t=[t]);for(var i=0;i<t.length;i++)t[i][c]=t[i][c]||{skipTest:e.skipTest},p(t[i]);n&&(document.body.addEventListener("load",function(t){"IMG"===t.target.tagName&&m(t.target,{skipTest:e.skipTest})},!0),s=!0,t="img"),e.watchMQ&&window.addEventListener("resize",m.bind(null,t,{skipTest:e.skipTest}))}function b(t,e){return t[c]&&t[c].img&&("src"===e||"srcset"===e)?t[c].img:t}m.supportsObjectFit=a,(m.supportsObjectPosition=o)||(HTMLImageElement.prototype.getAttribute=function(t){return h.call(b(this,t),t)},HTMLImageElement.prototype.setAttribute=function(t,e){return f.call(b(this,t),t,String(e))}),t.exports=m}}]);
//# sourceMappingURL=extra_polyfills-b58863fe161502239ec3.chunk.js.map