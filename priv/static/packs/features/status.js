(window.webpackJsonp=window.webpackJsonp||[]).push([[40],{649:function(e,t,a){"use strict";a.d(t,"a",function(){return x});var r=a(0),i=a(2),s=a(6),o=a(1),n=a(3),d=a.n(n),c=a(5),l=a.n(c),u=a(26),p=a.n(u),h=a(194),b=a(195),g=a(209),f=a(496),O=a(502),m=a(358),j=a(7),v=a(497),M=a(25),y=a(132),k=a(642),_=a(12),C=a.n(_),R=a(30),w=a(503),x=function(n){function e(){for(var a,e=arguments.length,t=new Array(e),s=0;s<e;s++)t[s]=arguments[s];return a=n.call.apply(n,[this].concat(t))||this,Object(o.a)(Object(i.a)(a),"state",{height:null}),Object(o.a)(Object(i.a)(a),"handleAccountClick",function(e){0!==e.button||e.ctrlKey||e.metaKey||!a.context.router||(e.preventDefault(),a.context.router.history.push("/accounts/"+a.props.status.getIn(["account","id"]))),e.stopPropagation()}),Object(o.a)(Object(i.a)(a),"handleOpenVideo",function(e,t){a.props.onOpenVideo(e,t)}),Object(o.a)(Object(i.a)(a),"handleExpandedToggle",function(){a.props.onToggleHidden(a.props.status)}),Object(o.a)(Object(i.a)(a),"setRef",function(e){a.node=e,a._measureHeight()}),Object(o.a)(Object(i.a)(a),"handleModalLink",function(e){var t;e.preventDefault(),t="A"!==e.target.nodeName?e.target.parentNode.href:e.target.href,window.open(t,"mastodon-intent","width=445,height=600,resizable=no,menubar=no,status=no,scrollbars=yes")}),a}Object(s.a)(e,n);var t=e.prototype;return t._measureHeight=function(e){var t=this;this.props.measureHeight&&this.node&&(Object(k.a)(function(){return t.node&&t.setState({height:Math.ceil(t.node.scrollHeight)+1})}),this.props.onHeightChange&&e&&this.props.onHeightChange())},t.componentDidUpdate=function(e,t){this._measureHeight(t.height!==this.state.height)},t.render=function(){var e=this.props.status&&this.props.status.get("reblog")?this.props.status.get("reblog"):this.props.status,t={boxSizing:"border-box"},a=this.props.compact;if(!e)return null;var s="",n="",i="",o="retweet",c="";if(this.props.measureHeight&&(t.height=this.state.height+"px"),e.get("poll"))s=Object(r.a)(w.a,{pollId:e.get("poll")});else if(0<e.get("media_attachments").size)if(e.get("media_attachments").some(function(e){return"unknown"===e.get("type")}))s=Object(r.a)(O.a,{media:e.get("media_attachments")});else if("video"===e.getIn(["media_attachments",0,"type"])){var l=e.getIn(["media_attachments",0]);s=Object(r.a)(y.default,{preview:l.get("preview_url"),src:l.get("url"),alt:l.get("description"),width:300,height:150,inline:!0,onOpenVideo:this.handleOpenVideo,sensitive:e.get("sensitive")})}else s=Object(r.a)(f.default,{standalone:!0,sensitive:e.get("sensitive"),media:e.get("media_attachments"),height:300,onOpenMedia:this.props.onOpenMedia});else 0===e.get("spoiler_text").length&&(s=Object(r.a)(v.a,{onOpenMedia:this.props.onOpenMedia,card:e.get("card",null)}));return e.get("application")&&(n=Object(r.a)("span",{},void 0," · ",Object(r.a)("a",{className:"detailed-status__application",href:e.getIn(["application","website"]),target:"_blank",rel:"noopener"},void 0,e.getIn(["application","name"])))),"direct"===e.get("visibility")?o="envelope":"private"===e.get("visibility")&&(o="lock"),i="private"===e.get("visibility")?Object(r.a)(R.a,{id:o}):this.context.router?Object(r.a)(m.a,{to:"/statuses/"+e.get("id")+"/reblogs",className:"detailed-status__link"},void 0,Object(r.a)(R.a,{id:o}),Object(r.a)("span",{className:"detailed-status__reblogs"},void 0,Object(r.a)(j.c,{value:e.get("reblogs_count")}))):Object(r.a)("a",{href:"/interact/"+e.get("id")+"?type=reblog",className:"detailed-status__link",onClick:this.handleModalLink},void 0,Object(r.a)(R.a,{id:o}),Object(r.a)("span",{className:"detailed-status__reblogs"},void 0,Object(r.a)(j.c,{value:e.get("reblogs_count")}))),c=this.context.router?Object(r.a)(m.a,{to:"/statuses/"+e.get("id")+"/favourites",className:"detailed-status__link"},void 0,Object(r.a)(R.a,{id:"star"}),Object(r.a)("span",{className:"detailed-status__favorites"},void 0,Object(r.a)(j.c,{value:e.get("favourites_count")}))):Object(r.a)("a",{href:"/interact/"+e.get("id")+"?type=favourite",className:"detailed-status__link",onClick:this.handleModalLink},void 0,Object(r.a)(R.a,{id:"star"}),Object(r.a)("span",{className:"detailed-status__favorites"},void 0,Object(r.a)(j.c,{value:e.get("favourites_count")}))),Object(r.a)("div",{style:t},void 0,d.a.createElement("div",{ref:this.setRef,className:C()("detailed-status",{compact:a})},Object(r.a)("a",{href:e.getIn(["account","url"]),onClick:this.handleAccountClick,className:"detailed-status__display-name"},void 0,Object(r.a)("div",{className:"detailed-status__display-avatar"},void 0,Object(r.a)(h.a,{account:e.get("account"),size:48})),Object(r.a)(b.a,{account:e.get("account"),localDomain:this.props.domain})),Object(r.a)(g.a,{status:e,expanded:!e.get("hidden"),onExpandedToggle:this.handleExpandedToggle}),s,Object(r.a)("div",{className:"detailed-status__meta"},void 0,Object(r.a)("a",{className:"detailed-status__datetime",href:e.get("url"),target:"_blank",rel:"noopener"},void 0,Object(r.a)(j.a,{value:new Date(e.get("created_at")),hour12:!1,year:"numeric",month:"short",day:"2-digit",hour:"2-digit",minute:"2-digit"})),n," · ",i," · ",c)))},e}(M.a);Object(o.a)(x,"contextTypes",{router:l.a.object}),Object(o.a)(x,"propTypes",{status:p.a.map,onOpenMedia:l.a.func.isRequired,onOpenVideo:l.a.func.isRequired,onToggleHidden:l.a.func.isRequired,measureHeight:l.a.bool,onHeightChange:l.a.func,domain:l.a.string.isRequired,compact:l.a.bool})},714:function(e,t,a){"use strict";a.r(t);var s,n,i,o,c,l,r,u=a(0),d=a(2),p=a(6),h=a(1),b=a(4),g=a.n(b),f=a(3),O=a.n(f),m=a(21),j=a(5),v=a.n(j),M=a(12),y=a.n(M),k=a(26),_=a.n(k),C=a(86),R=a(897),w=a(649),x=a(67),I=a(637),D=a(7),H=a(24),N=Object(D.f)({delete:{id:"status.delete",defaultMessage:"Delete"},redraft:{id:"status.redraft",defaultMessage:"Delete & re-draft"},direct:{id:"status.direct",defaultMessage:"Direct message @{name}"},mention:{id:"status.mention",defaultMessage:"Mention @{name}"},reply:{id:"status.reply",defaultMessage:"Reply"},reblog:{id:"status.reblog",defaultMessage:"Boost"},reblog_private:{id:"status.reblog_private",defaultMessage:"Boost to original audience"},cancel_reblog_private:{id:"status.cancel_reblog_private",defaultMessage:"Unboost"},cannot_reblog:{id:"status.cannot_reblog",defaultMessage:"This post cannot be boosted"},favourite:{id:"status.favourite",defaultMessage:"Favourite"},mute:{id:"status.mute",defaultMessage:"Mute @{name}"},muteConversation:{id:"status.mute_conversation",defaultMessage:"Mute conversation"},unmuteConversation:{id:"status.unmute_conversation",defaultMessage:"Unmute conversation"},block:{id:"status.block",defaultMessage:"Block @{name}"},report:{id:"status.report",defaultMessage:"Report @{name}"},share:{id:"status.share",defaultMessage:"Share"},pin:{id:"status.pin",defaultMessage:"Pin on profile"},unpin:{id:"status.unpin",defaultMessage:"Unpin from profile"},embed:{id:"status.embed",defaultMessage:"Embed"},admin_account:{id:"status.admin_account",defaultMessage:"Open moderation interface for @{name}"},admin_status:{id:"status.admin_status",defaultMessage:"Open this status in the moderation interface"},copy:{id:"status.copy",defaultMessage:"Copy link to status"}}),A=Object(D.g)((i=n=function(n){function e(){for(var a,e=arguments.length,t=new Array(e),s=0;s<e;s++)t[s]=arguments[s];return a=n.call.apply(n,[this].concat(t))||this,Object(h.a)(Object(d.a)(a),"handleReplyClick",function(){a.props.onReply(a.props.status)}),Object(h.a)(Object(d.a)(a),"handleReblogClick",function(e){a.props.onReblog(a.props.status,e)}),Object(h.a)(Object(d.a)(a),"handleFavouriteClick",function(){a.props.onFavourite(a.props.status)}),Object(h.a)(Object(d.a)(a),"handleDeleteClick",function(){a.props.onDelete(a.props.status,a.context.router.history)}),Object(h.a)(Object(d.a)(a),"handleRedraftClick",function(){a.props.onDelete(a.props.status,a.context.router.history,!0)}),Object(h.a)(Object(d.a)(a),"handleDirectClick",function(){a.props.onDirect(a.props.status.get("account"),a.context.router.history)}),Object(h.a)(Object(d.a)(a),"handleMentionClick",function(){a.props.onMention(a.props.status.get("account"),a.context.router.history)}),Object(h.a)(Object(d.a)(a),"handleMuteClick",function(){a.props.onMute(a.props.status.get("account"))}),Object(h.a)(Object(d.a)(a),"handleConversationMuteClick",function(){a.props.onMuteConversation(a.props.status)}),Object(h.a)(Object(d.a)(a),"handleBlockClick",function(){a.props.onBlock(a.props.status)}),Object(h.a)(Object(d.a)(a),"handleReport",function(){a.props.onReport(a.props.status)}),Object(h.a)(Object(d.a)(a),"handlePinClick",function(){a.props.onPin(a.props.status)}),Object(h.a)(Object(d.a)(a),"handleShare",function(){navigator.share({text:a.props.status.get("search_index"),url:a.props.status.get("url")})}),Object(h.a)(Object(d.a)(a),"handleEmbed",function(){a.props.onEmbed(a.props.status)}),Object(h.a)(Object(d.a)(a),"handleCopy",function(){var e=a.props.status.get("url"),t=document.createElement("textarea");t.textContent=e,t.style.position="fixed",document.body.appendChild(t);try{t.select(),document.execCommand("copy")}catch(e){}finally{document.body.removeChild(t)}}),a}return Object(p.a)(e,n),e.prototype.render=function(){var e=this.props,t=e.status,a=e.intl,s=["public","unlisted"].includes(t.get("visibility")),n=t.get("muted"),i=[];s&&(i.push({text:a.formatMessage(N.copy),action:this.handleCopy}),i.push({text:a.formatMessage(N.embed),action:this.handleEmbed}),i.push(null)),H.k===t.getIn(["account","id"])?(s?i.push({text:a.formatMessage(t.get("pinned")?N.unpin:N.pin),action:this.handlePinClick}):"private"===t.get("visibility")&&i.push({text:a.formatMessage(t.get("reblogged")?N.cancel_reblog_private:N.reblog_private),action:this.handleReblogClick}),i.push(null),i.push({text:a.formatMessage(n?N.unmuteConversation:N.muteConversation),action:this.handleConversationMuteClick}),i.push(null),i.push({text:a.formatMessage(N.delete),action:this.handleDeleteClick}),i.push({text:a.formatMessage(N.redraft),action:this.handleRedraftClick})):(i.push({text:a.formatMessage(N.mention,{name:t.getIn(["account","username"])}),action:this.handleMentionClick}),i.push({text:a.formatMessage(N.direct,{name:t.getIn(["account","username"])}),action:this.handleDirectClick}),i.push(null),i.push({text:a.formatMessage(N.mute,{name:t.getIn(["account","username"])}),action:this.handleMuteClick}),i.push({text:a.formatMessage(N.block,{name:t.getIn(["account","username"])}),action:this.handleBlockClick}),i.push({text:a.formatMessage(N.report,{name:t.getIn(["account","username"])}),action:this.handleReport}),H.i&&(i.push(null),i.push({text:a.formatMessage(N.admin_account,{name:t.getIn(["account","username"])}),href:"/admin/accounts/"+t.getIn(["account","id"])}),i.push({text:a.formatMessage(N.admin_status),href:"/admin/accounts/"+t.getIn(["account","id"])+"/statuses/"+t.get("id")})));var o,c="share"in navigator&&"public"===t.get("visibility")&&Object(u.a)("div",{className:"detailed-status__button"},void 0,Object(u.a)(x.a,{title:a.formatMessage(N.share),icon:"share-alt",onClick:this.handleShare}));o=null===t.get("in_reply_to_id",null)?"reply":"reply-all";var l="retweet";"direct"===t.get("visibility")?l="envelope":"private"===t.get("visibility")&&(l="lock");var r="direct"===t.get("visibility")||"private"===t.get("visibility");return Object(u.a)("div",{className:"detailed-status__action-bar"},void 0,Object(u.a)("div",{className:"detailed-status__button"},void 0,Object(u.a)(x.a,{title:a.formatMessage(N.reply),icon:t.get("in_reply_to_account_id")===t.getIn(["account","id"])?"reply":o,onClick:this.handleReplyClick})),Object(u.a)("div",{className:"detailed-status__button"},void 0,Object(u.a)(x.a,{disabled:r,active:t.get("reblogged"),title:r?a.formatMessage(N.cannot_reblog):a.formatMessage(N.reblog),icon:l,onClick:this.handleReblogClick})),Object(u.a)("div",{className:"detailed-status__button"},void 0,Object(u.a)(x.a,{className:"star-icon",animate:!0,active:t.get("favourited"),title:a.formatMessage(N.favourite),icon:"star",onClick:this.handleFavouriteClick})),c,Object(u.a)("div",{className:"detailed-status__action-bar-dropdown"},void 0,Object(u.a)(I.a,{size:18,icon:"ellipsis-h",items:i,direction:"left",title:"More"})))},e}(O.a.PureComponent),Object(h.a)(n,"contextTypes",{router:v.a.object}),s=i))||s,T=a(626),S=a(58),B=a(22),E=a(27),F=a(196),U=a(94),z=a(200),P=a(427),V=a(629),q=a(628),K=a(903),L=a(57),J=a(25),W=a(343),X=a(230),G=a(769),Q=a(30);a.d(t,"default",function(){return Z});var Y=Object(D.f)({deleteConfirm:{id:"confirmations.delete.confirm",defaultMessage:"Delete"},deleteMessage:{id:"confirmations.delete.message",defaultMessage:"Are you sure you want to delete this status?"},redraftConfirm:{id:"confirmations.redraft.confirm",defaultMessage:"Delete & redraft"},redraftMessage:{id:"confirmations.redraft.message",defaultMessage:"Are you sure you want to delete this status and re-draft it? Favourites and boosts will be lost, and replies to the original post will be orphaned."},blockConfirm:{id:"confirmations.block.confirm",defaultMessage:"Block"},revealAll:{id:"status.show_more_all",defaultMessage:"Show more for all"},hideAll:{id:"status.show_less_all",defaultMessage:"Show less for all"},detailedStatus:{id:"status.detailed_status",defaultMessage:"Detailed conversation view"},replyConfirm:{id:"confirmations.reply.confirm",defaultMessage:"Reply"},replyMessage:{id:"confirmations.reply.message",defaultMessage:"Replying now will overwrite the message you are currently composing. Are you sure you want to proceed?"},blockAndReport:{id:"confirmations.block.block_and_report",defaultMessage:"Block & Report"}}),Z=(o=Object(m.connect)(function(){var s=Object(z.f)();return function(n,e){var i=s(n,{id:e.params.statusId}),t=g.a.List(),a=g.a.List();return i&&(t=t.withMutations(function(e){for(var t=i.get("in_reply_to_id");t;)e.unshift(t),t=n.getIn(["contexts","inReplyTos",t])}),a=a.withMutations(function(e){for(var t=[i.get("id")];0<t.length;){var a=t.shift(),s=n.getIn(["contexts","replies",a]);i.get("id")!==a&&e.push(a),s&&s.reverse().forEach(function(e){t.unshift(e)})}})),{status:i,ancestorsIds:t,descendantsIds:a,askReplyConfirmation:0!==n.getIn(["compose","text"]).trim().length,domain:n.getIn(["meta","domain"])}}}),Object(D.g)(c=o((r=l=function(s){function e(){for(var o,e=arguments.length,t=new Array(e),a=0;a<e;a++)t[a]=arguments[a];return o=s.call.apply(s,[this].concat(t))||this,Object(h.a)(Object(d.a)(o),"state",{fullscreen:!1}),Object(h.a)(Object(d.a)(o),"handleFavouriteClick",function(e){e.get("favourited")?o.props.dispatch(Object(S.p)(e)):o.props.dispatch(Object(S.k)(e))}),Object(h.a)(Object(d.a)(o),"handlePin",function(e){e.get("pinned")?o.props.dispatch(Object(S.q)(e)):o.props.dispatch(Object(S.n)(e))}),Object(h.a)(Object(d.a)(o),"handleReplyClick",function(e){var t=o.props,a=t.askReplyConfirmation,s=t.dispatch,n=t.intl;s(a?Object(L.d)("CONFIRM",{message:n.formatMessage(Y.replyMessage),confirm:n.formatMessage(Y.replyConfirm),onConfirm:function(){return s(Object(B.fb)(e,o.context.router.history))}}):Object(B.fb)(e,o.context.router.history))}),Object(h.a)(Object(d.a)(o),"handleModalReblog",function(e){o.props.dispatch(Object(S.o)(e))}),Object(h.a)(Object(d.a)(o),"handleReblogClick",function(e,t){e.get("reblogged")?o.props.dispatch(Object(S.r)(e)):t&&t.shiftKey||!H.b?o.handleModalReblog(e):o.props.dispatch(Object(L.d)("BOOST",{status:e,onReblog:o.handleModalReblog}))}),Object(h.a)(Object(d.a)(o),"handleDeleteClick",function(e,t,a){void 0===a&&(a=!1);var s=o.props,n=s.dispatch,i=s.intl;H.d?n(Object(L.d)("CONFIRM",{message:i.formatMessage(a?Y.redraftMessage:Y.deleteMessage),confirm:i.formatMessage(a?Y.redraftConfirm:Y.deleteConfirm),onConfirm:function(){return n(Object(C.g)(e.get("id"),t,a))}})):n(Object(C.g)(e.get("id"),t,a))}),Object(h.a)(Object(d.a)(o),"handleDirectClick",function(e,t){o.props.dispatch(Object(B.X)(e,t))}),Object(h.a)(Object(d.a)(o),"handleMentionClick",function(e,t){o.props.dispatch(Object(B.bb)(e,t))}),Object(h.a)(Object(d.a)(o),"handleOpenMedia",function(e,t){o.props.dispatch(Object(L.d)("MEDIA",{media:e,index:t}))}),Object(h.a)(Object(d.a)(o),"handleOpenVideo",function(e,t){o.props.dispatch(Object(L.d)("VIDEO",{media:e,time:t}))}),Object(h.a)(Object(d.a)(o),"handleMuteClick",function(e){o.props.dispatch(Object(F.g)(e))}),Object(h.a)(Object(d.a)(o),"handleConversationMuteClick",function(e){e.get("muted")?o.props.dispatch(Object(C.l)(e.get("id"))):o.props.dispatch(Object(C.j)(e.get("id")))}),Object(h.a)(Object(d.a)(o),"handleToggleHidden",function(e){e.get("hidden")?o.props.dispatch(Object(C.k)(e.get("id"))):o.props.dispatch(Object(C.i)(e.get("id")))}),Object(h.a)(Object(d.a)(o),"handleToggleAll",function(){var e=o.props,t=e.status,a=e.ancestorsIds,s=e.descendantsIds,n=[t.get("id")].concat(a.toJS(),s.toJS());t.get("hidden")?o.props.dispatch(Object(C.k)(n)):o.props.dispatch(Object(C.i)(n))}),Object(h.a)(Object(d.a)(o),"handleBlockClick",function(e){var t=o.props,a=t.dispatch,s=t.intl,n=e.get("account");a(Object(L.d)("CONFIRM",{message:Object(u.a)(D.b,{id:"confirmations.block.message",defaultMessage:"Are you sure you want to block {name}?",values:{name:Object(u.a)("strong",{},void 0,"@",n.get("acct"))}}),confirm:s.formatMessage(Y.blockConfirm),onConfirm:function(){return a(Object(E.w)(n.get("id")))},secondary:s.formatMessage(Y.blockAndReport),onSecondary:function(){a(Object(E.w)(n.get("id"))),a(Object(U.k)(n,e))}}))}),Object(h.a)(Object(d.a)(o),"handleReport",function(e){o.props.dispatch(Object(U.k)(e.get("account"),e))}),Object(h.a)(Object(d.a)(o),"handleEmbed",function(e){o.props.dispatch(Object(L.d)("EMBED",{url:e.get("url")}))}),Object(h.a)(Object(d.a)(o),"handleHotkeyMoveUp",function(){o.handleMoveUp(o.props.status.get("id"))}),Object(h.a)(Object(d.a)(o),"handleHotkeyMoveDown",function(){o.handleMoveDown(o.props.status.get("id"))}),Object(h.a)(Object(d.a)(o),"handleHotkeyReply",function(e){e.preventDefault(),o.handleReplyClick(o.props.status)}),Object(h.a)(Object(d.a)(o),"handleHotkeyFavourite",function(){o.handleFavouriteClick(o.props.status)}),Object(h.a)(Object(d.a)(o),"handleHotkeyBoost",function(){o.handleReblogClick(o.props.status)}),Object(h.a)(Object(d.a)(o),"handleHotkeyMention",function(e){e.preventDefault(),o.handleMentionClick(o.props.status.get("account"))}),Object(h.a)(Object(d.a)(o),"handleHotkeyOpenProfile",function(){o.context.router.history.push("/accounts/"+o.props.status.getIn(["account","id"]))}),Object(h.a)(Object(d.a)(o),"handleHotkeyToggleHidden",function(){o.handleToggleHidden(o.props.status)}),Object(h.a)(Object(d.a)(o),"handleMoveUp",function(e){var t=o.props,a=t.status,s=t.ancestorsIds,n=t.descendantsIds;if(e===a.get("id"))o._selectChild(s.size-1);else{var i=s.indexOf(e);-1===i?(i=n.indexOf(e),o._selectChild(s.size+i)):o._selectChild(i-1)}}),Object(h.a)(Object(d.a)(o),"handleMoveDown",function(e){var t=o.props,a=t.status,s=t.ancestorsIds,n=t.descendantsIds;if(e===a.get("id"))o._selectChild(s.size+1);else{var i=s.indexOf(e);-1===i?(i=n.indexOf(e),o._selectChild(s.size+i+2)):o._selectChild(i+1)}}),Object(h.a)(Object(d.a)(o),"setRef",function(e){o.node=e}),Object(h.a)(Object(d.a)(o),"onFullScreenChange",function(){o.setState({fullscreen:Object(X.d)()})}),o}Object(p.a)(e,s);var t=e.prototype;return t.componentWillMount=function(){this.props.dispatch(Object(C.h)(this.props.params.statusId))},t.componentDidMount=function(){Object(X.a)(this.onFullScreenChange)},t.componentWillReceiveProps=function(e){e.params.statusId!==this.props.params.statusId&&e.params.statusId&&(this._scrolledIntoView=!1,this.props.dispatch(Object(C.h)(e.params.statusId)))},t._selectChild=function(e){var t=this.node.querySelectorAll(".focusable")[e];t&&t.focus()},t.renderChildren=function(e){var t=this;return e.map(function(e){return Object(u.a)(K.a,{id:e,onMoveUp:t.handleMoveUp,onMoveDown:t.handleMoveDown,contextType:"thread"},e)})},t.componentDidUpdate=function(){if(!this._scrolledIntoView){var e=this.props,t=e.status,a=e.ancestorsIds;if(t&&a&&0<a.size){var s=this.node.querySelectorAll(".focusable")[a.size-1];window.requestAnimationFrame(function(){s.scrollIntoView(!0)}),this._scrolledIntoView=!0}}},t.componentWillUnmount=function(){Object(X.b)(this.onFullScreenChange)},t.render=function(){var e,t,a=this.props,s=a.shouldUpdateScroll,n=a.status,i=a.ancestorsIds,o=a.descendantsIds,c=a.intl,l=a.domain,r=this.state.fullscreen;if(null===n)return Object(u.a)(T.a,{},void 0,Object(u.a)(V.a,{}),Object(u.a)(R.a,{}));i&&0<i.size&&(e=Object(u.a)("div",{},void 0,this.renderChildren(i))),o&&0<o.size&&(t=Object(u.a)("div",{},void 0,this.renderChildren(o)));var d={moveUp:this.handleHotkeyMoveUp,moveDown:this.handleHotkeyMoveDown,reply:this.handleHotkeyReply,favourite:this.handleHotkeyFavourite,boost:this.handleHotkeyBoost,mention:this.handleHotkeyMention,openProfile:this.handleHotkeyOpenProfile,toggleHidden:this.handleHotkeyToggleHidden};return Object(u.a)(T.a,{label:c.formatMessage(Y.detailedStatus)},void 0,Object(u.a)(q.a,{showBackButton:!0,extraButton:Object(u.a)("button",{className:"column-header__button",title:c.formatMessage(n.get("hidden")?Y.revealAll:Y.hideAll),"aria-label":c.formatMessage(n.get("hidden")?Y.revealAll:Y.hideAll),onClick:this.handleToggleAll,"aria-pressed":n.get("hidden")?"false":"true"},void 0,Object(u.a)(Q.a,{id:n.get("hidden")?"eye-slash":"eye"}))}),Object(u.a)(P.a,{scrollKey:"thread",shouldUpdateScroll:s},void 0,O.a.createElement("div",{className:y()("scrollable",{fullscreen:r}),ref:this.setRef},e,Object(u.a)(W.HotKeys,{handlers:d},void 0,Object(u.a)("div",{className:y()("focusable","detailed-status__wrapper"),tabIndex:"0","aria-label":Object(G.b)(c,n,!1)},void 0,Object(u.a)(w.a,{status:n,onOpenVideo:this.handleOpenVideo,onOpenMedia:this.handleOpenMedia,onToggleHidden:this.handleToggleHidden,domain:l}),Object(u.a)(A,{status:n,onReply:this.handleReplyClick,onFavourite:this.handleFavouriteClick,onReblog:this.handleReblogClick,onDelete:this.handleDeleteClick,onDirect:this.handleDirectClick,onMention:this.handleMentionClick,onMute:this.handleMuteClick,onMuteConversation:this.handleConversationMuteClick,onBlock:this.handleBlockClick,onReport:this.handleReport,onPin:this.handlePin,onEmbed:this.handleEmbed}))),t)))},e}(J.a),Object(h.a)(l,"contextTypes",{router:v.a.object}),Object(h.a)(l,"propTypes",{params:v.a.object.isRequired,dispatch:v.a.func.isRequired,status:_.a.map,ancestorsIds:_.a.list,descendantsIds:_.a.list,intl:v.a.object.isRequired,askReplyConfirmation:v.a.bool,domain:v.a.string.isRequired}),c=r))||c)||c)}}]);
//# sourceMappingURL=status.js.map