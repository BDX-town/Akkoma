(window.webpackJsonp=window.webpackJsonp||[]).push([[35],{1325:function(e,t,n){"use strict";(function(e){n.d(t,"a",(function(){return K}));var a,i,o,s=n(0),c=n(2),r=n(9),u=n(6),l=n(8),d=n(1),m=n(3),p=n.n(m),h=n(21),b=n(216),f=n.n(b),j=n(16),g=n.n(j),v=n(5),O=n.n(v),_=n(53),y=n(27),R=n(7),M=n(22),k=n(83),C=n.n(k),x=n(14),w=n.n(x),A=n(546),I=n(590),E=n(473),N=n.n(E),L=n(35),P=n.n(L);function S(e){return function(){var t,n=Object(u.a)(e);if(q()){var a=Object(u.a)(this).constructor;t=Reflect.construct(n,arguments,a)}else t=n.apply(this,arguments);return Object(r.a)(this,t)}}function q(){if("undefined"==typeof Reflect||!Reflect.construct)return!1;if(Reflect.construct.sham)return!1;if("function"==typeof Proxy)return!0;try{return Date.prototype.toString.call(Reflect.construct(Date,[],(function(){}))),!0}catch(e){return!1}}var D=Object(R.f)({close:{id:"lightbox.close",defaultMessage:"Close"},previous:{id:"lightbox.previous",defaultMessage:"Previous"},next:{id:"lightbox.next",defaultMessage:"Next"}}),z=function(e){Object(l.a)(t,e);S(t);function t(){for(var t,n=arguments.length,a=new Array(n),i=0;i<n;i++)a[i]=arguments[i];return t=e.call.apply(e,[this].concat(a))||this,Object(d.a)(Object(c.a)(t),"setRef",(function(e){t.node=e})),Object(d.a)(Object(c.a)(t),"onMentionClick",(function(e,n){!t.context.router||0!==n.button||n.ctrlKey||n.metaKey||(n.preventDefault(),t.context.router.history.push("/accounts/"+e.get("id")))})),Object(d.a)(Object(c.a)(t),"onHashtagClick",(function(e,n){e=e.replace(/^#/,""),!t.context.router||0!==n.button||n.ctrlKey||n.metaKey||(n.preventDefault(),t.context.router.history.push("/timelines/tag/"+e))})),Object(d.a)(Object(c.a)(t),"onStatusClick",(function(e,n){!t.context.router||0!==n.button||n.ctrlKey||n.metaKey||(n.preventDefault(),t.context.router.history.push("/statuses/"+e.get("id")))})),Object(d.a)(Object(c.a)(t),"handleEmojiMouseEnter",(function(e){var t=e.target;t.src=t.getAttribute("data-original")})),Object(d.a)(Object(c.a)(t),"handleEmojiMouseLeave",(function(e){var t=e.target;t.src=t.getAttribute("data-static")})),t}var n=t.prototype;return n.componentDidMount=function(){this._updateLinks(),this._updateEmojis()},n.componentDidUpdate=function(){this._updateLinks(),this._updateEmojis()},n._updateEmojis=function(){var e=this.node;if(e&&!M.a)for(var t=e.querySelectorAll(".custom-emoji"),n=0;n<t.length;n++){var a=t[n];a.classList.contains("status-emoji")||(a.classList.add("status-emoji"),a.addEventListener("mouseenter",this.handleEmojiMouseEnter,!1),a.addEventListener("mouseleave",this.handleEmojiMouseLeave,!1))}},n._updateLinks=function(){var e=this,t=this.node;if(t)for(var n=t.querySelectorAll("a"),a=function(){var t=n[i];if(t.classList.contains("status-link"))return"continue";t.classList.add("status-link");var a=e.props.announcement.get("mentions").find((function(e){return t.href===e.get("url")}));if(a)t.addEventListener("click",e.onMentionClick.bind(e,a),!1),t.setAttribute("title",a.get("acct"));else if("#"===t.textContent[0]||t.previousSibling&&t.previousSibling.textContent&&"#"===t.previousSibling.textContent[t.previousSibling.textContent.length-1])t.addEventListener("click",e.onHashtagClick.bind(e,t.text),!1);else{var o=e.props.announcement.get("statuses").find((function(e){return t.href===e.get("url")}));o&&t.addEventListener("click",e.onStatusClick.bind(e,o),!1),t.setAttribute("title",t.href),t.classList.add("unhandled-link")}t.setAttribute("target","_blank"),t.setAttribute("rel","noopener noreferrer")},i=0;i<n.length;++i)a()},n.render=function(){var e=this.props.announcement;return(p.a.createElement("div",{className:"announcements__item__content",ref:this.setRef,dangerouslySetInnerHTML:{__html:e.get("contentHtml")}}))},t}(h.a);Object(d.a)(z,"contextTypes",{router:O.a.object}),Object(d.a)(z,"propTypes",{announcement:g.a.map.isRequired});var T=e.env.CDN_HOST||"",H=function(e){Object(l.a)(t,e);S(t);function t(){return e.apply(this,arguments)||this}return t.prototype.render=function(){var e=this.props,t=e.emoji,n=e.emojiMap,a=e.hovered;if(C.a[t]){var i=C.a[this.props.emoji],o=i.filename,c=i.shortCode,r=c?":"+c+":":"";return Object(s.a)("img",{draggable:"false",className:"emojione",alt:t,title:r,src:T+"/emoji/"+o+".svg"})}if(n.get(t)){var u=M.a||a?n.getIn([t,"url"]):n.getIn([t,"static_url"]),l=":"+t+":";return Object(s.a)("img",{draggable:"false",className:"emojione custom-emoji",alt:l,title:l,src:u})}return null},t}(p.a.PureComponent),F=function(e){Object(l.a)(t,e);S(t);function t(){for(var t,n=arguments.length,a=new Array(n),i=0;i<n;i++)a[i]=arguments[i];return t=e.call.apply(e,[this].concat(a))||this,Object(d.a)(Object(c.a)(t),"state",{hovered:!1}),Object(d.a)(Object(c.a)(t),"handleClick",(function(){var e=t.props,n=e.reaction,a=e.announcementId,i=e.addReaction,o=e.removeReaction;n.get("me")?o(a,n.get("name")):i(a,n.get("name"))})),Object(d.a)(Object(c.a)(t),"handleMouseEnter",(function(){return t.setState({hovered:!0})})),Object(d.a)(Object(c.a)(t),"handleMouseLeave",(function(){return t.setState({hovered:!1})})),t}return t.prototype.render=function(){var e=this.props.reaction,t=e.get("name");return C.a[t]&&(t=C.a[t].shortCode),Object(s.a)("button",{className:w()("reactions-bar__item",{active:e.get("me")}),onClick:this.handleClick,onMouseEnter:this.handleMouseEnter,onMouseLeave:this.handleMouseLeave,title:":"+t+":",style:this.props.style},void 0,Object(s.a)("span",{className:"reactions-bar__item__emoji"},void 0,Object(s.a)(H,{hovered:this.state.hovered,emoji:e.get("name"),emojiMap:this.props.emojiMap})),Object(s.a)("span",{className:"reactions-bar__item__count"},void 0,Object(s.a)(I.a,{value:e.get("count")})))},t}(h.a);Object(d.a)(F,"propTypes",{announcementId:O.a.string.isRequired,reaction:g.a.map.isRequired,addReaction:O.a.func.isRequired,removeReaction:O.a.func.isRequired,emojiMap:g.a.map.isRequired,style:O.a.object});var Y=function(e){Object(l.a)(t,e);S(t);function t(){for(var t,n=arguments.length,a=new Array(n),i=0;i<n;i++)a[i]=arguments[i];return t=e.call.apply(e,[this].concat(a))||this,Object(d.a)(Object(c.a)(t),"handleEmojiPick",(function(e){var n=t.props;(0,n.addReaction)(n.announcementId,e.native.replace(/:/g,""))})),t}var n=t.prototype;return n.willEnter=function(){return{scale:M.p?1:0}},n.willLeave=function(){return{scale:M.p?0:P()(0,{stiffness:170,damping:26})}},n.render=function(){var e=this,t=this.props.reactions.filter((function(e){return e.get("count")>0})),n=t.map((function(e){return{key:e.get("name"),data:e,style:{scale:M.p?1:P()(1,{stiffness:150,damping:13})}}})).toArray();return Object(s.a)(N.a,{styles:n,willEnter:this.willEnter,willLeave:this.willLeave},void 0,(function(n){return Object(s.a)("div",{className:w()("reactions-bar",{"reactions-bar--empty":t.isEmpty()})},void 0,n.map((function(t){var n=t.key,a=t.data,i=t.style;return(Object(s.a)(F,{reaction:a,style:{transform:"scale("+i.scale+")",position:i.scale<.5?"absolute":"static"},announcementId:e.props.announcementId,addReaction:e.props.addReaction,removeReaction:e.props.removeReaction,emojiMap:e.props.emojiMap},n))})),t.size<8&&Object(s.a)(A.a,{onPickEmoji:e.handleEmojiPick,button:Object(s.a)(y.a,{id:"plus"})}))}))},t}(h.a);Object(d.a)(Y,"propTypes",{announcementId:O.a.string.isRequired,reactions:g.a.list.isRequired,addReaction:O.a.func.isRequired,removeReaction:O.a.func.isRequired,emojiMap:g.a.map.isRequired});var U=function(e){Object(l.a)(t,e);S(t);function t(){for(var t,n=arguments.length,a=new Array(n),i=0;i<n;i++)a[i]=arguments[i];return t=e.call.apply(e,[this].concat(a))||this,Object(d.a)(Object(c.a)(t),"state",{unread:!t.props.announcement.get("read")}),t}var n=t.prototype;return n.componentDidUpdate=function(){var e=this.props,t=e.selected,n=e.announcement;t||this.state.unread===!n.get("read")||this.setState({unread:!n.get("read")})},n.render=function(){var e=this.props.announcement,t=this.state.unread,n=e.get("starts_at")&&new Date(e.get("starts_at")),a=e.get("ends_at")&&new Date(e.get("ends_at")),i=new Date,o=n&&a,c=o&&n.getFullYear()===a.getFullYear()&&a.getFullYear()===i.getFullYear(),r=o&&n.getDate()===a.getDate()&&n.getMonth()===a.getMonth()&&n.getFullYear()===a.getFullYear(),u=e.get("all_day");return Object(s.a)("div",{className:"announcements__item"},void 0,Object(s.a)("strong",{className:"announcements__item__range"},void 0,Object(s.a)(R.b,{id:"announcement.announcement",defaultMessage:"Announcement"}),o&&Object(s.a)("span",{},void 0," · ",Object(s.a)(R.a,{value:n,hour12:!1,year:c||n.getFullYear()===i.getFullYear()?void 0:"numeric",month:"short",day:"2-digit",hour:u?void 0:"2-digit",minute:u?void 0:"2-digit"})," - ",Object(s.a)(R.a,{value:a,hour12:!1,year:c||a.getFullYear()===i.getFullYear()?void 0:"numeric",month:r?void 0:"short",day:r?void 0:"2-digit",hour:u?void 0:"2-digit",minute:u?void 0:"2-digit"}))),Object(s.a)(z,{announcement:e}),Object(s.a)(Y,{reactions:e.get("reactions"),announcementId:e.get("id"),addReaction:this.props.addReaction,removeReaction:this.props.removeReaction,emojiMap:this.props.emojiMap}),t&&Object(s.a)("span",{className:"announcements__item__unread"}))},t}(h.a);Object(d.a)(U,"propTypes",{announcement:g.a.map.isRequired,emojiMap:g.a.map.isRequired,addReaction:O.a.func.isRequired,removeReaction:O.a.func.isRequired,intl:O.a.object.isRequired,selected:O.a.bool});var K=Object(R.g)((o=i=function(e){Object(l.a)(t,e);S(t);function t(){for(var t,n=arguments.length,a=new Array(n),i=0;i<n;i++)a[i]=arguments[i];return t=e.call.apply(e,[this].concat(a))||this,Object(d.a)(Object(c.a)(t),"state",{index:0}),Object(d.a)(Object(c.a)(t),"handleChangeIndex",(function(e){t.setState({index:e%t.props.announcements.size})})),Object(d.a)(Object(c.a)(t),"handleNextClick",(function(){t.setState({index:(t.state.index+1)%t.props.announcements.size})})),Object(d.a)(Object(c.a)(t),"handlePrevClick",(function(){t.setState({index:(t.props.announcements.size+t.state.index-1)%t.props.announcements.size})})),t}t.getDerivedStateFromProps=function(e,t){return e.announcements.size>0&&t.index>=e.announcements.size?{index:e.announcements.size-1}:null};var n=t.prototype;return n.componentDidMount=function(){this._markAnnouncementAsRead()},n.componentDidUpdate=function(){this._markAnnouncementAsRead()},n._markAnnouncementAsRead=function(){var e=this.props,t=e.dismissAnnouncement,n=e.announcements,a=this.state.index,i=n.get(a);i.get("read")||t(i.get("id"))},n.render=function(){var e=this,t=this.props,n=t.announcements,a=t.intl,i=this.state.index;return n.isEmpty()?null:Object(s.a)("div",{className:"announcements"},void 0,"mascot && ( ",Object(s.a)("img",{className:"announcements__mastodon",alt:"",draggable:"false",src:M.l})," )",Object(s.a)("div",{className:"announcements__container"},void 0,Object(s.a)(f.a,{animateHeight:!M.p,adjustHeight:M.p,index:i,onChangeIndex:this.handleChangeIndex},void 0,n.map((function(t,n){return Object(s.a)(U,{announcement:t,emojiMap:e.props.emojiMap,addReaction:e.props.addReaction,removeReaction:e.props.removeReaction,intl:a,selected:i===n},t.get("id"))}))),n.size>1&&Object(s.a)("div",{className:"announcements__pagination"},void 0,Object(s.a)(_.a,{disabled:1===n.size,title:a.formatMessage(D.previous),icon:"chevron-left",onClick:this.handlePrevClick,size:13}),Object(s.a)("span",{},void 0,i+1," / ",n.size),Object(s.a)(_.a,{disabled:1===n.size,title:a.formatMessage(D.next),icon:"chevron-right",onClick:this.handleNextClick,size:13}))))},t}(h.a),Object(d.a)(i,"propTypes",{announcements:g.a.list,emojiMap:g.a.map.isRequired,dismissAnnouncement:O.a.func.isRequired,addReaction:O.a.func.isRequired,removeReaction:O.a.func.isRequired,intl:O.a.object.isRequired}),a=o))||a}).call(this,n(50))},728:function(e,t,n){"use strict";var a=n(0),i=(n(3),n(27));t.a=function(e){var t,n=e.id,o=e.count,s=e.className;return(Object(a.a)("i",{className:"icon-with-badge"},void 0,Object(a.a)(i.a,{id:n,fixedWidth:!0,className:s}),o>0&&Object(a.a)("i",{className:"icon-with-badge__badge"},void 0,(t=o)>40?"40+":t)))}},842:function(e,t,n){"use strict";n.r(t),n.d(t,"default",(function(){return L}));var a,i=n(0),o=n(2),s=(n(9),n(6),n(8)),c=n(1),r=n(3),u=n.n(r),l=n(15),d=n(36),m=n(1063),p=n(762),h=n(759),b=n(253),f=n(7),j=n(1107);var g,v=Object(f.g)(a=function(e){Object(s.a)(n,e);var t;t=n;function n(){return e.apply(this,arguments)||this}return n.prototype.render=function(){var e=this.props,t=e.settings,n=e.onChange;return(Object(i.a)("div",{},void 0,Object(i.a)("span",{className:"column-settings__section"},void 0,Object(i.a)(f.b,{id:"home.column_settings.basic",defaultMessage:"Basic"})),Object(i.a)("div",{className:"column-settings__row"},void 0,Object(i.a)(j.a,{prefix:"home_timeline",settings:t,settingPath:["shows","reblog"],onChange:n,label:Object(i.a)(f.b,{id:"home.column_settings.show_reblogs",defaultMessage:"Show boosts"})})),Object(i.a)("div",{className:"column-settings__row"},void 0,Object(i.a)(j.a,{prefix:"home_timeline",settings:t,settingPath:["shows","reply"],onChange:n,label:Object(i.a)(f.b,{id:"home.column_settings.show_replies",defaultMessage:"Show replies"})}))))},n}(u.a.PureComponent))||a,O=n(74),_=Object(l.connect)((function(e){return{settings:e.getIn(["settings","home"])}}),(function(e){return{onChange:function(t,n){e(Object(O.c)(["home"].concat(t),n))},onSave:function(){e(Object(O.d)())}}}))(v),y=n(322),R=n(72),M=n(1325),k=n(57),C=n(4),x=Object(k.a)([function(e){return e.get("custom_emojis")}],(function(e){return e.reduce((function(e,t){return e.set(t.get("shortcode"),t)}),Object(C.Map)())})),w=Object(l.connect)((function(e){return{announcements:e.getIn(["announcements","items"]),emojiMap:x(e)}}),(function(e){return{dismissAnnouncement:function(t){return e(Object(R.o)(t))},addReaction:function(t,n){return e(Object(R.m)(t,n))},removeReaction:function(t,n){return e(Object(R.q)(t,n))}}}))(M.a),A=n(14),I=n.n(A),E=n(728);var N=Object(f.f)({title:{id:"column.home",defaultMessage:"Home"},show_announcements:{id:"home.show_announcements",defaultMessage:"Show announcements"},hide_announcements:{id:"home.hide_announcements",defaultMessage:"Hide announcements"}}),L=Object(l.connect)((function(e){return{hasUnread:e.getIn(["timelines","home","unread"])>0,isPartial:e.getIn(["timelines","home","isPartial"]),hasAnnouncements:!e.getIn(["announcements","items"]).isEmpty(),unreadAnnouncements:e.getIn(["announcements","items"]).count((function(e){return!e.get("read")})),showAnnouncements:e.getIn(["announcements","show"])}}))(g=Object(f.g)(g=function(e){Object(s.a)(n,e);var t;t=n;function n(){for(var t,n=arguments.length,a=new Array(n),i=0;i<n;i++)a[i]=arguments[i];return t=e.call.apply(e,[this].concat(a))||this,Object(c.a)(Object(o.a)(t),"handlePin",(function(){var e=t.props,n=e.columnId,a=e.dispatch;a(n?Object(b.h)(n):Object(b.e)("HOME",{}))})),Object(c.a)(Object(o.a)(t),"handleMove",(function(e){var n=t.props,a=n.columnId;(0,n.dispatch)(Object(b.g)(a,e))})),Object(c.a)(Object(o.a)(t),"handleHeaderClick",(function(){t.column.scrollTop()})),Object(c.a)(Object(o.a)(t),"setRef",(function(e){t.column=e})),Object(c.a)(Object(o.a)(t),"handleLoadMore",(function(e){t.props.dispatch(Object(d.t)({maxId:e}))})),Object(c.a)(Object(o.a)(t),"handleToggleAnnouncementsClick",(function(e){e.stopPropagation(),t.props.dispatch(Object(R.r)())})),t}var a=n.prototype;return a.componentDidMount=function(){this.props.dispatch(Object(R.p)()),this._checkIfReloadNeeded(!1,this.props.isPartial)},a.componentDidUpdate=function(e){this._checkIfReloadNeeded(e.isPartial,this.props.isPartial)},a.componentWillUnmount=function(){this._stopPolling()},a._checkIfReloadNeeded=function(e,t){var n=this.props.dispatch;e!==t&&(!e&&t?this.polling=setInterval((function(){n(Object(d.t)())}),3e3):e&&!t&&this._stopPolling())},a._stopPolling=function(){this.polling&&(clearInterval(this.polling),this.polling=null)},a.render=function(){var e=this.props,t=e.intl,n=e.shouldUpdateScroll,a=e.hasUnread,o=e.columnId,s=e.multiColumn,c=e.hasAnnouncements,r=e.unreadAnnouncements,l=e.showAnnouncements,d=!!o,b=null;return c&&(b=Object(i.a)("button",{className:I()("column-header__button",{active:l}),title:t.formatMessage(l?N.hide_announcements:N.show_announcements),"aria-label":t.formatMessage(l?N.hide_announcements:N.show_announcements),"aria-pressed":l?"true":"false",onClick:this.handleToggleAnnouncementsClick},void 0,Object(i.a)(E.a,{id:"bullhorn",count:r}))),u.a.createElement(p.a,{bindToDocument:!s,ref:this.setRef,label:t.formatMessage(N.title)},Object(i.a)(h.a,{icon:"home",active:a,title:t.formatMessage(N.title),onPin:this.handlePin,onMove:this.handleMove,onClick:this.handleHeaderClick,pinned:d,multiColumn:s,extraButton:b,appendContent:c&&l&&Object(i.a)(w,{})},void 0,Object(i.a)(_,{})),Object(i.a)(m.a,{trackScroll:!d,scrollKey:"home_timeline-"+o,onLoadMore:this.handleLoadMore,timelineId:"home",emptyMessage:Object(i.a)(f.b,{id:"empty_column.home",defaultMessage:"Your home timeline is empty! Visit {public} or use search to get started and meet other users.",values:{public:Object(i.a)(y.a,{to:"/timelines/public"},void 0,Object(i.a)(f.b,{id:"empty_column.home.public_timeline",defaultMessage:"the public timeline"}))}}),shouldUpdateScroll:n,bindToDocument:!s}))},n}(u.a.PureComponent))||g)||g}}]);
//# sourceMappingURL=home_timeline.js.map