(window.webpackJsonp=window.webpackJsonp||[]).push([[81],{752:function(e,t,a){"use strict";a.r(t);var n,o,i,r=a(0),s=a(2),c=a(7),d=a(1),l=a(3),u=a.n(l),b=a(12),p=a(98),h=a(33),g=a(5),m=a.n(g),v=a(18),O=a.n(v),j=a(148),f=a(6),w=a(295),_=a.n(w),y=a(1075),C=a.n(y),k=a(150),I=a(37),M=a(302),N=function(e){function t(){return e.apply(this,arguments)||this}return Object(c.a)(t,e),t.prototype.render=function(){var e=this.props,t=e.status,a=e.checked,n=e.onToggle,o=e.disabled,i=null;if(t.get("reblog"))return null;if(t.get("media_attachments").size>0)if(t.get("media_attachments").some(function(e){return"unknown"===e.get("type")}));else if("video"===t.getIn(["media_attachments",0,"type"])){var s=t.getIn(["media_attachments",0]);i=Object(r.a)(M.a,{fetchComponent:I.Q,loading:this.renderLoadingVideoPlayer},void 0,function(e){return Object(r.a)(e,{preview:s.get("preview_url"),blurhash:s.get("blurhash"),src:s.get("url"),alt:s.get("description"),width:239,height:110,inline:!0,sensitive:t.get("sensitive"),revealed:!1,onOpenVideo:C.a})})}else i=Object(r.a)(M.a,{fetchComponent:I.C,loading:this.renderLoadingMediaGallery},void 0,function(e){return Object(r.a)(e,{media:t.get("media_attachments"),sensitive:t.get("sensitive"),revealed:!1,height:110,onOpenMedia:C.a})});return Object(r.a)("div",{className:"status-check-box"},void 0,Object(r.a)("div",{className:"status-check-box__status"},void 0,Object(r.a)(k.a,{status:t,media:i})),Object(r.a)("div",{className:"status-check-box-toggle"},void 0,Object(r.a)(_.a,{checked:a,onChange:n,disabled:o})))},t}(u.a.PureComponent),S=a(4),x=Object(b.connect)(function(e,t){var a=t.id;return{status:e.getIn(["statuses",a]),checked:e.getIn(["reports","new","status_ids"],Object(S.Set)()).includes(a)}},function(e,t){var a=t.id;return{onToggle:function(t){e(Object(p.m)(a,t.target.checked))}}})(N),R=a(19),q=a(68),F=a(40);a.d(t,"default",function(){return T});var K=Object(f.f)({close:{id:"lightbox.close",defaultMessage:"Close"},placeholder:{id:"report.placeholder",defaultMessage:"Additional comments"},submit:{id:"report.submit",defaultMessage:"Submit"}}),T=Object(b.connect)(function(){var e=Object(j.d)();return function(t){var a=t.getIn(["reports","new","account_id"]);return{isSubmitting:t.getIn(["reports","new","isSubmitting"]),account:e(t,a),comment:t.getIn(["reports","new","comment"]),forward:t.getIn(["reports","new","forward"]),statusIds:Object(S.OrderedSet)(t.getIn(["timelines","account:"+a+":with_replies","items"])).union(t.getIn(["reports","new","status_ids"]))}}})(n=Object(f.g)((i=o=function(e){function t(){for(var t,a=arguments.length,n=new Array(a),o=0;o<a;o++)n[o]=arguments[o];return t=e.call.apply(e,[this].concat(n))||this,Object(d.a)(Object(s.a)(t),"handleCommentChange",function(e){t.props.dispatch(Object(p.i)(e.target.value))}),Object(d.a)(Object(s.a)(t),"handleForwardChange",function(e){t.props.dispatch(Object(p.j)(e.target.checked))}),Object(d.a)(Object(s.a)(t),"handleSubmit",function(){t.props.dispatch(Object(p.l)())}),Object(d.a)(Object(s.a)(t),"handleKeyDown",function(e){13===e.keyCode&&(e.ctrlKey||e.metaKey)&&t.handleSubmit()}),t}Object(c.a)(t,e);var a=t.prototype;return a.componentDidMount=function(){this.props.dispatch(Object(h.q)(this.props.account.get("id"),{withReplies:!0}))},a.componentWillReceiveProps=function(e){this.props.account!==e.account&&e.account&&this.props.dispatch(Object(h.q)(e.account.get("id"),{withReplies:!0}))},a.render=function(){var e=this.props,t=e.account,a=e.comment,n=e.intl,o=e.statusIds,i=e.isSubmitting,s=e.forward,c=e.onClose;if(!t)return null;var d=t.get("acct").split("@")[1];return Object(r.a)("div",{className:"modal-root__modal report-modal"},void 0,Object(r.a)("div",{className:"report-modal__target"},void 0,Object(r.a)(F.a,{className:"media-modal__close",title:n.formatMessage(K.close),icon:"times",onClick:c,size:16}),Object(r.a)(f.b,{id:"report.target",defaultMessage:"Report {target}",values:{target:Object(r.a)("strong",{},void 0,t.get("acct"))}})),Object(r.a)("div",{className:"report-modal__container"},void 0,Object(r.a)("div",{className:"report-modal__comment"},void 0,Object(r.a)("p",{},void 0,Object(r.a)(f.b,{id:"report.hint",defaultMessage:"The report will be sent to your server moderators. You can provide an explanation of why you are reporting this account below:"})),Object(r.a)("textarea",{className:"setting-text light",placeholder:n.formatMessage(K.placeholder),value:a,onChange:this.handleCommentChange,onKeyDown:this.handleKeyDown,disabled:i,autoFocus:!0}),d&&Object(r.a)("div",{},void 0,Object(r.a)("p",{},void 0,Object(r.a)(f.b,{id:"report.forward_hint",defaultMessage:"The account is from another server. Send an anonymized copy of the report there as well?"})),Object(r.a)("div",{className:"setting-toggle"},void 0,Object(r.a)(_.a,{id:"report-forward",checked:s,disabled:i,onChange:this.handleForwardChange}),Object(r.a)("label",{htmlFor:"report-forward",className:"setting-toggle__label"},void 0,Object(r.a)(f.b,{id:"report.forward",defaultMessage:"Forward to {target}",values:{target:d}})))),Object(r.a)(q.a,{disabled:i,text:n.formatMessage(K.submit),onClick:this.handleSubmit})),Object(r.a)("div",{className:"report-modal__statuses"},void 0,Object(r.a)("div",{},void 0,o.map(function(e){return Object(r.a)(x,{id:e,disabled:i},e)})))))},t}(R.a),Object(d.a)(o,"propTypes",{isSubmitting:m.a.bool,account:O.a.map,statusIds:O.a.orderedSet.isRequired,comment:m.a.string.isRequired,forward:m.a.bool,dispatch:m.a.func.isRequired,intl:m.a.object.isRequired}),n=i))||n)||n}}]);
//# sourceMappingURL=report_modal.js.map