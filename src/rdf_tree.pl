/*  File:    tree.pl
    Author:  Jan Wielemaker
    Created: Jun  3 2003
    Purpose: Visualise RDF hierarchy
*/

:- module(rdf_tree, []).
:- use_module(library(pce)).
:- use_module(library(pce_unclip)).
:- use_module(semweb(rdf_db)).
:- use_module(semweb(rdfs)).
:- use_module(particle).
:- use_module(rdf_template).
:- use_module(rdf_cache).


		 /*******************************
		 *	     HIERARCHY		*
		 *******************************/

:- pce_begin_class(rdf_tree, tree,
		   "Display an RDF hierarchy").

variable(selectable,	 chain*,      both, "Roles of selectable nodes").
variable(message,	 code*,	      both, "Message on select").
variable(open_message,	 code*,	      both, "Message  on double-click").

:- pce_global(@onto_tree_recogniser,
	      make_onto_tree_recogniser).

make_onto_tree_recogniser(R) :-
	new(R, handler_group),
	send(R, append, click_gesture(left, '', single,
				      message(@receiver, on_left_click))),
	send(R, append, new(KB, key_binding)),
	send(KB, function, '\\ef', find).

initialise(H, Root:[name]) :->
	send_super(H, initialise),
	(   Root == @default
	->  rdf_equal(rdfs:'Resource', TheRoot)
	;   TheRoot = Root
	),
	send(H, direction, list),
	send(H, level_gap, 20),
	new(RootNode, rdf_node(TheRoot)),
%	call_rules(H, root_node(TheRoot, RootNode)),
	send(H, root, RootNode).

expand_root(H) :->
	"Expand the root node"::
	get(H, root, Root),
	send(Root, collapsed, @off).

:- pce_group(build).

member(OT, Id:name, Node:rdf_node) :<-
	"Find Node representing ID"::
	get(OT?root, find, @arg1?resource == Id, Node).

add(OT, Id:name, Role:[name]) :->
	"Add node for Id to the tree, as well as the path"::
	get(OT, add, Id, Role, _Node).

add(OT, Resource:name, _Role:[name], Node:rdf_node) :<-
	"Expand the tree to show a resource"::
	(   get(OT, member, Resource, Node)
	->  true
	;   get(OT?root, resource, Root),
	    findall(Path, path(Resource, Root, OT, Path), [P0|_Paths]),
	    display_path(P0, OT, Node)
	).
	
path(Resource, Resource, _, [Resource-[]]) :- !.
path(Resource, Root, Tree, [Resource-Role|T]) :-
	call_rules(Tree, parent(Resource, Parent, Role)),
	path(Parent, Root, Tree, T).

display_path([H-Role|_], OT, Node) :-
	get(OT, member, H, Node),
	(   Role == []
	;   get(Node, class_name, Role)
	), !.
display_path([H-Role|T], OT, Node) :-
	display_path(T, OT, Parent),
	get(Parent, add_child, H, Role, Node),
	send_class(Parent, node, collapsed(@off)).


:- pce_group(event).

event(OT, Ev:event) :->
	"Deal with events"::
	(   send_super(OT, event, Ev)
	;   send(@onto_tree_recogniser, event, Ev)
	).

on_left_click(OT) :->
	"Deselect all nodes"::
	send(OT, selection, @nil).

selected(OT, Node:rdf_node) :->
	"User selected a node"::
	send(OT, selection, Node?image),
	(   get(OT, message, M),
	    M \== @nil
	->  get(Node, resource, Term),
	    send(M, forward, Term)	% @arg1 = term
	;   true
	).

open_node(OT, Node:rdf_node) :->
	"User double-clicked a node"::
	(   get(OT, open_message, M),
	    M \== @nil
	->  get(Node, resource, Term),
	    send(M, forward, Term)	% @arg1 = term
	;   true
	).

arm(_, _:bool) :->
	fail.

:- pce_end_class(rdf_tree).


		 /*******************************
		 *	       NODES		*
		 *******************************/

:- pce_begin_class(rdf_node, node,
		   "Node of an RDF hierarchy").

variable(resource,   name,                get,
	 "Represented resource").
variable(caches, sheet := new(sheet), get,
	 "Cached relations").

initialise(N, Resource:name) :->
	send(N, slot, resource, Resource),
	get(N, label, Label),
	send_super(N, initialise, Label),
	(   call_rules(N, child_cache(Resource, Cache, Role)),
	    send(N?caches, value, Role, Cache),
	    fail
	;   true
	),
	send(N, update_can_expand).


label(N, Label:graphical) :<-
	get(N, resource, Resource),
	call_rules(N, label(Resource, Label)).


update_can_expand(N) :->
	"Update expansion-state"::
	(   send(N, can_expand)
	->  send_super(N, collapsed, @on)
	;   send_super(N, collapsed, @nil)
	).

:- pce_group(expand).

collapsed(N, V:bool*) :->
	(   V == @on
	->  send(N?sons, for_all, message(@arg1, delete_tree))
	;   send(@display, busy_cursor),
	    call_cleanup(send(N, expand),
			 send(@display, busy_cursor, @nil))
	),
	send_super(N, collapsed, V).

can_expand(N) :->
	"Test whether this node has childs"::
	get(N?caches?members, find,
	    message(N, can_expand_cache, @arg1?value),
	    _).

can_expand_cache(_N, Cache:int) :->
	\+ rdf_cache_empty(Cache).

expand(N) :->
	"Expand this node"::
	send(N?caches?members, for_all,
	     message(N, expand_role, @arg1?name, @arg1?value)).

expand_role(N, Role:name, Cache:int) :->
	"Expand a cache"::
	rdf_cache_cardinality(Cache, SetSize),
	(   SetSize < 15
	->  forall(rdf_cache_result(Cache, I, Value),
		   send(N, add_child, Value, Role))
	;   rdf_cache_result(Cache, I, Value),
	    (	I == 11
	    ->	!,
		send(N, son, rdf_more_node(Role, SetSize, 11))
	    ;	send(N, add_child, Value, Role),
		fail
	    )
	;   true
	).

add_child(N, Resource:name, Role:name, Before:[node], Son:rdf_node) :<-
	"Create node for resource in role"::
	NewTerm =.. [Role, Resource],
	new(Son, NewTerm),
	send(N, son, Son, Before).

add_child(N, Resource:name, Role:name, Before:[node]) :->
	"Create node for resource in Role"::
	get(N, add_child, Resource, Role, Before, _Son).
	
show_more(N, MoreNode:rdf_more_node, Role:name, Count:int) :->
	"Show next Count nodes on Role"::
	get(N?caches, value, Role, Cache),
	get(MoreNode, here, Here),
	End is Here + Count,
	(   rdf_cache_result(Cache, I, Value),
	    I >= Here,
	    send(N, add_child, Value, Role, MoreNode),
	    I >= End, !
	;   true
	),
	rdf_cache_cardinality(Cache, Cardinality),
	(   End < Cardinality
	->  send(MoreNode, here, End)
	;   send(MoreNode, destroy)
	).
	
:- pce_group(event).

:- pce_global(@rdf_node_recogniser, make_rdf_node_recogniser).
:- pce_global(@rdf_node_popop, make_rdf_node_popup).

make_rdf_node_popup(Popup) :-
	Node = @arg1,
	new(Popup, popup(options)),
	send_list(Popup, append,
		  [ menu_item(delete,
			      message(Node, delete_resource))
		  ]).


make_rdf_node_recogniser(G) :-
	new(P, popup_gesture(@receiver?popup)),
	new(C1, click_gesture(left, '', single,
			      message(@receiver,
				      on_left_click))),
			      
	new(C2, click_gesture(left, '', double,
			      message(@receiver,
				      on_double_left_click))),
	new(G, handler_group(P, C1, C2)).
			      

popup(_, Popup:popup) :<-
	Popup = @rdf_node_popop.

event(N, Ev:event) :->
	"Handle node-event"::
	(   send_super(N, event, Ev)
	->  true
	;   send(Ev, post, N?image, @rdf_node_recogniser)
	).

on_left_click(N) :->
	"Select the current node"::
	send(N?tree, selected, N).

clicked(N, _:graphical) :->
	"Resource has been clicked inside me"::
	send(N, on_left_click).

on_double_left_click(N) :->
	"Select the current node"::
	get(N, class_name, Role),
	get(N?tree, selectable, Roles),
	(   (	Roles == @nil
	    ;	send(Roles, member, Role)
	    )
	->  send(N?tree, open_node, N)
	;   send(N, report, warning, 'Cannot open %s class', Role)
	).

:- pce_end_class(rdf_node).


:- pce_begin_class(rdf_class_node, rdf_node).
:- pce_end_class.


:- pce_begin_class(rdf_individual_node, rdf_node).
:- pce_end_class.


:- pce_begin_class(rdf_property_node, rdf_node).
:- pce_end_class.


:- pce_begin_class(owl_restriction_node, rdf_node).
:- pce_end_class.



		 /*******************************
		 *	   SHOW MORE ...	*
		 *******************************/

:- pce_begin_class(rdf_more_node, node,
		   "Show more alternatives").

variable(role,	   name,  get, "Role to expand further").
variable(here,	   int,	  get, "Current location").
variable(size,	   int,	  get, "Total set-size").
variable(resource, name*, get, "Represented resource (@nil)").

initialise(N, Role:name, Size:int, Here:int) :->
	"Create `more' button"::
	send_super(N, initialise, new(D, figure)),
	send(N, slot, role, Role),
	send(N, slot, size, Size),
	send(N, slot, here, Here),
	send(D, pen, 1),
	send(D, border, 2),
	send(D, format, new(Fmt, format(vertical, 1, @on))),
	send(Fmt, adjustment, vector(center)),
	send(N, update_more),
	send(N, collapsed, @nil).

update_more(N) :->
	"Update	displayed buttons"::
	get(N, image, D),
	send(D, clear),
	send(D, display, text('Next', left, bold)),
	get(N, size, Size),
	get(N, here, Here),
	Left is Size - Here,
	(   Left < 10
	->  send(D, display, more_button(Left))
	;   Left < 100
	->  send(D, display, more_button(10)),
	    send(D, display, more_button(Left))
	;   Left < 1000
	->  send(D, display, more_button(10)),
	    send(D, display, more_button(100)),
	    send(D, display, more_button(Left))
	;   send(D, display, more_button(10)),
	    send(D, display, more_button(100)),
	    send(D, display, more_button(1000)),
	    send(D, display, text(string('(showing %d of %d) ', Here, Size), left, italic))
	).

update_label(_) :->
	"Dummy"::
	true.

update_expandable(_) :->
	"Dummy"::
	true.

refresh(_) :->
	"Dummy"::
	true.

here(N, Here:int) :->
	send(N, slot, here, Here),
	send(N, update_more).

more(N, More:[int]) :->
	"Show N more childs on this role"::
	get(N, parents, chain(Parent)),
	get(N, role, Role),
	send(Parent, show_more, N, Role, More).

:- pce_end_class(rdf_more_node).


		 /*******************************
		 *	    SMALL BUTTON	*
		 *******************************/

:- pce_begin_class(more_button, button,
		   "Button with minimal size").

class_variable(size, size, size(5,5)).

initialise(B, More:int) :->
	send_super(B, initialise, More,
		   message(B?device?node, more, More)),
	send(B, show_focus_border, @off).

:- pce_end_class(more_button).
