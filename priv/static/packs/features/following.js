(window.webpackJsonp=window.webpackJsonp||[]).push([[26],{727:function(a,t,o){"use strict";o.r(t),o.d(t,"default",function(){return _});var c,e,n,s=o(0),r=o(2),i=o(7),p=o(1),u=o(63),d=o.n(u),l=(o(3),o(12)),b=o(19),h=o(5),m=o.n(h),f=o(18),j=o.n(f),I=o(294),O=o(26),y=o(6),w=o(966),g=o(663),v=o(998),M=o(666),k=o(964),A=o(970),_=Object(l.connect)(function(a,t){return{isAccount:!!a.getIn(["accounts",t.params.accountId]),accountIds:a.getIn(["user_lists","following",t.params.accountId,"items"]),hasMore:!!a.getIn(["user_lists","following",t.params.accountId,"next"]),blockedBy:a.getIn(["relationships",t.params.accountId,"blocked_by"],!1)}})((n=e=function(a){function t(){for(var t,o=arguments.length,c=new Array(o),e=0;e<o;e++)c[e]=arguments[e];return t=a.call.apply(a,[this].concat(c))||this,Object(p.a)(Object(r.a)(t),"handleLoadMore",d()(function(){t.props.dispatch(Object(O.z)(t.props.params.accountId))},300,{leading:!0})),t}Object(i.a)(t,a);var o=t.prototype;return o.componentWillMount=function(){this.props.accountIds||(this.props.dispatch(Object(O.A)(this.props.params.accountId)),this.props.dispatch(Object(O.D)(this.props.params.accountId)))},o.componentWillReceiveProps=function(a){a.params.accountId!==this.props.params.accountId&&a.params.accountId&&(this.props.dispatch(Object(O.A)(a.params.accountId)),this.props.dispatch(Object(O.D)(a.params.accountId)))},o.render=function(){var a=this.props,t=a.shouldUpdateScroll,o=a.accountIds,c=a.hasMore,e=a.blockedBy,n=a.isAccount,r=a.multiColumn;if(!n)return Object(s.a)(g.a,{},void 0,Object(s.a)(A.a,{}));if(!o)return Object(s.a)(g.a,{},void 0,Object(s.a)(I.a,{}));var i=e?Object(s.a)(y.b,{id:"empty_column.account_unavailable",defaultMessage:"Profile unavailable"}):Object(s.a)(y.b,{id:"account.follows.empty",defaultMessage:"This user doesn't follow anyone yet."});return Object(s.a)(g.a,{},void 0,Object(s.a)(M.a,{multiColumn:r}),Object(s.a)(k.a,{scrollKey:"following",hasMore:c,onLoadMore:this.handleLoadMore,shouldUpdateScroll:t,prepend:Object(s.a)(v.a,{accountId:this.props.params.accountId,hideTabs:!0}),alwaysPrepend:!0,emptyMessage:i,bindToDocument:!r},void 0,e?[]:o.map(function(a){return Object(s.a)(w.a,{id:a,withNote:!1},a)})))},t}(b.a),Object(p.a)(e,"propTypes",{params:m.a.object.isRequired,dispatch:m.a.func.isRequired,shouldUpdateScroll:m.a.func,accountIds:j.a.list,hasMore:m.a.bool,blockedBy:m.a.bool,isAccount:m.a.bool,multiColumn:m.a.bool}),c=n))||c}}]);
//# sourceMappingURL=following.js.map