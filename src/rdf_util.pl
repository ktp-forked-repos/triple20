/*  $Id$

    Developed in the MIA project
    Designed and implemented by Jan Wielemaker
    E-mail: jan@swi.psy.uva.nl

    Copyright (C) 2000 University of Amsterdam. All rights reserved.
*/

:- module(rdf_util,
	  [ property_domain/3,		% +Subject, +Property, -Domain
	    property_type/3,		% +Subject, +Property, -Type
	    sort_by_label/2		% +Resources, -Sorted
	  ]).
:- use_module(semweb(rdf_db)).
:- use_module(semweb(rdfs)).
:- use_module(owl).

%	property_domain(+Subject, +Property, -Domain)
%	
%	Determine the domain of this property. Note that if the domain
%	is a class we want the selector to select a class by browsing
%	the class-hierarchy.  There is some issue around meta-classes
%	here.  Maybe we need class(Root, Meta)!

property_domain(Subject, Property, Domain) :-
	findall(R, property_restriction(Subject, Property, R), List),
	sort(List, Set),
	(   Set = [Domain]
	->  true
	;   Domain = intersection_of(Set)
	).

property_restriction(_, Property, R) :-
	rdf_has(Property, rdfs:range, Range),
	adjust_restriction(all_values_from(Range), R).
property_restriction(Subject, Property, R) :-
	rdf_has(Subject, rdf:type, Class),
	owl_restriction_on(Class, restriction(Property, R0)),
	adjust_restriction(R0, R).
	
adjust_restriction(cardinality(_,_), _) :- !,
	fail.
adjust_restriction(all_values_from(Class), class(Root)) :-
	rdfs_subclass_of(Class, rdfs:'Class'), !,
	rdf_equal(Root, rdfs:'Resource').
adjust_restriction(R, R).


%	property_type(+Subject, +Property, -Type)
%	
%	Classify the type of the object. For now the return values are
%	one of `resource' and `literal'.  May be extended in the future.

property_type(Subject, Property, Type) :-
	property_domain(Subject, Property, Domain),
	(   Domain = all_values_from(LiteralClass),
	    rdfs_subclass_of(LiteralClass, rdfs:'Literal')
	->  Type = literal
	;   Type = resource
	).

%	sort_by_label(+Resources, -Sorted)
%	
%	Sort a list of resources by `ns'-label. This version does *not*
%	remove duplicates.

sort_by_label(Resources, Sorted) :-
	tag_label(Resources, Tagged),
	keysort(Tagged, Sorted0),
	unkey(Sorted0, Sorted).

tag_label([], []).
tag_label([H|T0], [K-H|T]) :-
	rdfs_ns_label(H, K),
	tag_label(T0, T).

unkey([], []).
unkey([_-H|T0], [H|T]) :-
	unkey(T0, T).