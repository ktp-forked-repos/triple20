/*  File:    rdf_text.pl
    Author:  Jan Wielemaker
    Created: Jun 25 2003
    Purpose: Generic and specialized text objects
*/

:- module(rdf_text, []).
:- use_module(library(pce)).
:- use_module(owl).
:- use_module(semweb(rdf_edit)).

:- pce_autoload(editable_text,		 library(pce_editable_text)).

:- pce_begin_class(rdf_resource_text, text,
		   "Visualize a resource as a text object").

variable(resource,  name,  get, "Represented resource").
class_variable(colour, colour, blue).

initialise(T, Resource:name, Container:[object]) :->
	"Create from resource and table"::
	get(Container, node_label, Resource, Label),
	send_super(T, initialise, Label),
	send(T, slot, resource, Resource).

resource(T, Resource:name) :->
	"Modify the represented resource"::
	(   get(T, resource, Resource)
	->  true
	;   send(T, slot, resource, Resource),
	    get(T, device, Table),
	    get(Table, node_label, Resource, Label),
	    send(T, string, Label)
	).

:- pce_global(@rdf_resource_text_popup,
	      make_resource_text_popup).
:- pce_global(@rdf_resource_text_recogniser,
	      make_resource_text_recogniser).

make_resource_text_popup(P) :-
	new(P, popup),
	send_list(P, append,
		  [ menu_item(hierarchy_location,
			      message(@arg1, show_details, hierarchy),
			      condition := message(@arg1,
						   can_show_details,
						   hierarchy)),
		    menu_item(details,
			      message(@arg1, show_details, table),
			      condition := message(@arg1,
						   can_show_details,
						   table)),
		    menu_item(view_rdf_source,
			      message(@arg1, view_rdf_source))
		  ]).


make_resource_text_recogniser(G) :-
	new(CG, click_gesture(left, '', single,
			      message(@receiver, show_details, hierarchy))),
	new(PG, popup_gesture(@receiver?popup)),
	new(G, handler_group(CG, PG)).

popup(_T, Popup:popup) :<-
	Popup = @rdf_resource_text_popup.

event(T, Ev:event) :->
	(   send_super(T, event, Ev)
	;   send(@rdf_resource_text_recogniser, event, Ev)
	).

:- pce_group(edit).

show_details(T, How:{hierarchy,table}) :->
	"Show details in format"::
	(   get(T, frame, Frame),
	    send(Frame, has_send_method, show_resource)
	->  get(T, resource, Resource),
	    send(Frame, show_resource, Resource, How)
	).

can_show_details(T, _How:{hierarchy,table}) :->
	"Test if we are embedded in a context that can show details"::
	get(T, frame, Frame),
	send(Frame, has_send_method, show_resource).


view_rdf_source(T) :->
	"Open Prolog editor on RDF source"::
	get(T, resource, Id),
	(   rdf_source_location(Id, File:Line)
	->  edit(file(File, line(Line)))
	;   send(T, report, warning, 'Cannot find source for %s', Id)
	).

prompt(T, Subject:name, Property:name, Default:[name], Label:[name]) :->
	"Prompt for a (new) value"::
	get(T, device, AL),
	send(AL, prompt_value,
	     message(T, edited, @arg1, @arg2),
	     Subject,
	     Property,
	     Default,
	     Label,
	     T).

:- pce_end_class(rdf_resource_text).


:- pce_begin_class(rdf_object_text, rdf_resource_text,
		   "Represent the object-part of a triple").

variable(subject,   name*, get, "RDF subject").
variable(predicate, name*, get, "RDF predicate").

initialise(T,
	   Subject:subject=name,
	   Predicate:predicate=name,
	   Value:object=name,
	   Table:container=[object]) :->
	send_super(T, initialise, Value, Table),
	send(T, slot, subject, Subject),
	send(T, slot, predicate, Predicate).

refresh(T) :->
	get(T, subject, Subject),
	get(T, predicate, Predicate),
	rdf(Subject, Predicate, Value),
	(   atom(Value)
	->  send(T, resource, Value),
	    send(T, background, @nil)
	;   send(T, string, '<no resource>'),
	    send(T, background, red)
	).

:- pce_global(@rdf_object_text_popup,
	      make_object_text_popup).

make_object_text_popup(@Ref) :-
	get(@rdf_resource_text_popup, clone, P),
	send(P, name_reference, Ref),
	send_list(P, append,
		  [ gap,
		    menu_item(modify,
			      message(@arg1, modify)),
		    menu_item(delete,
			      message(@arg1, delete))
		  ]).

popup(_T, Popup:popup) :<-
	Popup = @rdf_object_text_popup.

modify(T) :->
	"Modify the value"::
	get(T, subject, Subject),
	get(T, predicate, Predicate),
	get(T, resource, Object),
	send(T, prompt, Subject, Predicate, Object).

edited(T, New:name, _Type:name) :->
	"A new values was set by the user"::
	get(T, subject, Subject),
	get(T, predicate, Property),
	get(T, resource, Old),
	(   Old \== New
	->  rdfe_transaction(rdfe_update(Subject, Property, Old,
					 object(New)))
	;   true
	).

delete(T) :->
	"Delete the value"::
	send(@display, confirm, 'Really delete?'),
	get(T, subject, Subject),
	get(T, predicate, Property),
	get(T, resource, Old),
	rdfe_transaction(rdfe_retractall(Subject, Property, Old)).

:- pce_end_class(rdf_object_text).


:- pce_begin_class(rdf_predicate_text, rdf_resource_text,
		   "Represent a predicate").

variable(subject,   name*, get, "RDF subject").

initialise(T,
	   Subject:subject=name,
	   Predicate:predicate=name,
	   Container:container=[object]) :->
	send_super(T, initialise, Predicate, Container),
	send(T, slot, subject, Subject).

:- pce_global(@rdf_predicate_text_popup,
	      make_predicate_text_popup).

make_predicate_text_popup(P) :-
	new(P, popup),
	send_list(P, append,
		  [ menu_item(hierarchy_location,
			      message(@arg1, show_details, hierarchy)),
		    menu_item(details,
			      message(@arg1, show_details, table)),
		    menu_item(view_rdf_source,
			      message(@arg1, view_rdf_source)),
		    gap,
		    menu_item(add_value,
			      message(@arg1, add_value),
			      condition := message(@arg1, can_add_value))
		  ]).

popup(_T, Popup:popup) :<-
	Popup = @rdf_predicate_text_popup.

can_add_value(T) :->
	"Test cardinality constraints"::
	(   get(T, cardinality_restriction, cardinality(_Min, Max))
	->  get(T, cardinality, Count),
	    Count < Max
	;   true			% Nothing known
	).

add_value(T) :->
	"Prompt for a new value"::
	get(T, window, Window),
	get(T, subject, Subject),
	get(T, resource, Predicate),
	get(Window, node_label, Subject, SubjectLabel),
	get(Window, node_label, Predicate, PropertyLabel),
	new(Label, string('Extend %s of %s', PropertyLabel, SubjectLabel)),
	send(T, prompt, Subject, Predicate, @default, Label).

edited(T, Value:name, Type:{literal,resource}) :->
	"A new values was set by the user"::
	get(T, subject, Subject),
	get(T, resource, Predicate),
	(   Type == literal
	->  Object = literal(Value)
	;   Object = Value
	),
	rdfe_transaction(rdfe_assert(Subject, Predicate, Object)).

cardinality(T, Count:int) :<-
	"Count facts on this property"::
	get(T, subject, Subject),
	get(T, resource, Predicate),
					% TBD: use rdf_has()?
	findall(V, rdf(Subject, Predicate, V), L),
	length(L, Count).

cardinality_restriction(T, Card:prolog) :<-
	"Get the cardinality constraints"::
	get(T, subject, Subject),
	get(T, resource, Predicate),
	owl_cardinality_on_subject(Subject, Predicate, Card).

:- pce_end_class(rdf_predicate_text).


		 /*******************************
		 *	   LITERAL TEXT		*
		 *******************************/


:- pce_begin_class(rdf_literal_text, editable_text,
		   "Text object for literal values").

variable(subject,   name*, get,	"RDF subject").
variable(predicate, name*, get,	"Represented predicate").
variable(literal,   name*, get, "Represented object (=value)").

initialise(LT,
	   Subject:subject=name,
	   Predicate:predicate=name,
	   Value:object=prolog,
	   _Container:container=[object]) :->
	(   Value = literal(Text)
	->  true
	;   Text = Value
	),
	send_super(LT, initialise, Text),
	send(LT, margin, 400, wrap),
	send(LT, slot, subject, Subject),
	send(LT, slot, predicate, Predicate),
	send(LT, slot, literal, Text).

refresh(LT) :->
	"Update represented text"::
	get(LT, subject, Subject),
	get(LT, predicate, Predicate),
	(   rdf(Subject, Predicate, literal(Text))
	->  send(LT, literal, Text),
	    send(LT, string, Text)
	;   send(LT, literal, @nil),
	    send(LT, string, '')
	).

object(LT, Object:prolog) :<-
	"Get RDF object: literal(Text)"::
	get(LT, literal, Text),
	Object = literal(Text).
	

obtain_focus(T) :->
	"Start editing"::
	(   get(T, show_caret, @on)
	->  send_super(T, obtain_focus)
	;   send_super(T, obtain_focus),
	    send(T, save_parameter, background),
	    send(T, border, 0),
	    send(T, pen, 0),
	    send(T, background, colour(white))
	).

:- pce_global(@rdf_literal_text_popup,
	      make_literal_text_popup).
:- pce_global(@rdf_literal_text_recogniser,
	      new(popup_gesture(@receiver?popup))).

make_literal_text_popup(P) :-
	new(P, popup),
	send_list(P, append,
		  [ menu_item(delete,
			      message(@arg1, delete))
		  ]).


popup(_T, Popup:popup) :<-
	Popup = @rdf_literal_text_popup.

event(T, Ev:event) :->
	(   send_super(T, event, Ev)
	;   send(@rdf_literal_text_recogniser, event, Ev)
	).

delete(T) :->
	"Delete associated triple"::
	get(T, subject, Subject),
	get(T, predicate, Predicate),
	get(T, object, Text),
	rdfe_transaction(rdfe_retractall(Subject, Predicate,
					 literal(Text))).

forward(T) :->
	"Set new value"::
	get(T, subject, Subject),
	get(T, predicate, Predicate),
	get(T, object, Object),
	get(T?string, value, NewText),
	New = literal(NewText),
	(   New \== Object
	->  rdfe_transaction(rdfe_update(Subject, Predicate,
				     Object, object(New)))
	;   true
	).

:- pce_end_class(rdf_literal_text).

