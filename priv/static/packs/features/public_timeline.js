(window.webpackJsonp=window.webpackJsonp||[]).push([[42],{765:function(e,n,t){"use strict";t.r(n);var o,i,c,a=t(0),l=t(2),d=t(7),r=t(1),s=t(3),u=t.n(s),p=t(12),b=t(6),h=t(5),m=t.n(h),f=t(977),j=t(669),O=t(665),M=t(35),g=t(245),y=t(1092),v=t(72),I=Object(p.connect)(function(e,n){var t=n.columnId,o=e.getIn(["settings","columns"]),i=o.findIndex(function(e){return e.get("uuid")===t});return{settings:t&&i>=0?o.get(i).get("params"):e.getIn(["settings","public"])}},function(e,n){var t=n.columnId;return{onChange:function(n,o){e(t?Object(g.f)(t,n,o):Object(v.c)(["public"].concat(n),o))}}})(y.a),w=t(672);t.d(n,"default",function(){return U});var C=Object(b.f)({title:{id:"column.public",defaultMessage:"Federated timeline"}}),U=Object(p.connect)(function(e,n){var t=n.onlyMedia,o=n.columnId,i=o,c=e.getIn(["settings","columns"]),a=c.findIndex(function(e){return e.get("uuid")===i});return{hasUnread:e.getIn(["timelines","public"+(t?":media":""),"unread"])>0,onlyMedia:o&&a>=0?c.get(a).getIn(["params","other","onlyMedia"]):e.getIn(["settings","public","other","onlyMedia"])}})(o=Object(b.g)((c=i=function(e){function n(){for(var n,t=arguments.length,o=new Array(t),i=0;i<t;i++)o[i]=arguments[i];return n=e.call.apply(e,[this].concat(o))||this,Object(r.a)(Object(l.a)(n),"handlePin",function(){var e=n.props,t=e.columnId,o=e.dispatch,i=e.onlyMedia;o(t?Object(g.h)(t):Object(g.e)("PUBLIC",{other:{onlyMedia:i}}))}),Object(r.a)(Object(l.a)(n),"handleMove",function(e){var t=n.props,o=t.columnId;(0,t.dispatch)(Object(g.g)(o,e))}),Object(r.a)(Object(l.a)(n),"handleHeaderClick",function(){n.column.scrollTop()}),Object(r.a)(Object(l.a)(n),"setRef",function(e){n.column=e}),Object(r.a)(Object(l.a)(n),"handleLoadMore",function(e){var t=n.props,o=t.dispatch,i=t.onlyMedia;o(Object(M.v)({maxId:e,onlyMedia:i}))}),n}Object(d.a)(n,e);var t=n.prototype;return t.componentDidMount=function(){var e=this.props,n=e.dispatch,t=e.onlyMedia;n(Object(M.v)({onlyMedia:t})),this.disconnect=n(Object(w.e)({onlyMedia:t}))},t.componentDidUpdate=function(e){if(e.onlyMedia!==this.props.onlyMedia){var n=this.props,t=n.dispatch,o=n.onlyMedia;this.disconnect(),t(Object(M.v)({onlyMedia:o})),this.disconnect=t(Object(w.e)({onlyMedia:o}))}},t.componentWillUnmount=function(){this.disconnect&&(this.disconnect(),this.disconnect=null)},t.render=function(){var e=this.props,n=e.intl,t=e.shouldUpdateScroll,o=e.columnId,i=e.hasUnread,c=e.multiColumn,l=e.onlyMedia,d=!!o;return u.a.createElement(j.a,{bindToDocument:!c,ref:this.setRef,label:n.formatMessage(C.title)},Object(a.a)(O.a,{icon:"globe",active:i,title:n.formatMessage(C.title),onPin:this.handlePin,onMove:this.handleMove,onClick:this.handleHeaderClick,pinned:d,multiColumn:c},void 0,Object(a.a)(I,{columnId:o})),Object(a.a)(f.a,{timelineId:"public"+(l?":media":""),onLoadMore:this.handleLoadMore,trackScroll:!d,scrollKey:"public_timeline-"+o,emptyMessage:Object(a.a)(b.b,{id:"empty_column.public",defaultMessage:"There is nothing here! Write something publicly, or manually follow users from other servers to fill it up"}),shouldUpdateScroll:t,bindToDocument:!c}))},n}(u.a.PureComponent),Object(r.a)(i,"contextTypes",{router:m.a.object}),Object(r.a)(i,"defaultProps",{onlyMedia:!1}),o=c))||o)||o}}]);
//# sourceMappingURL=public_timeline.js.map