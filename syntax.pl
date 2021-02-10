:- module(_,[
    op(1190,xfx,user:(if)),
    op(1187,xfx,user:(then)),
    op(1187,xfx,user:(must)),
    op(1185,fx,user:(if)),
    op(1185,xfy,user:else),
    op(1000,xfy,user:and), % same as ,
    op(1050,xfy,user:or), % same as ;
    op(900,fx,user:not), % same as \+
    op(700,xfx,user:in),
    op(600,xfx,user:on),
    op(1150,xfx,user:because), % to support because(on(p,t),why) if ...
    op(700,xfx,user:at), % note vs. negation...incompatible with LPS fluents
    % date operators
    op(700,xfx,user:not_before),
    op(700,xfx,user:before),
    op(700,xfx,user:after),
    taxlog2prolog/3
    ]).

:- use_module(kp_loader,[kp_location/3]).

:- use_module(library(prolog_xref)).
:- use_module(library(prolog_colour)).

/*
Transforms source rules into our "no time on heads" representation, using a body wrapper to carry extra information:
    taxlogBody(RealBody,Time,URL,Why)

P on T if Body  -->  P :- taxlogBody(Body,T,'',[])
P on T because Why :- PrologBody   -->   P :- taxlogBody(PrologBody,T,'',Why)
P if Body  --> P  :- taxlogBody(Body,_,'',[])
Admissible variants with a specific URL:
P on T at URL if Body --> P :- taxlogBody(Body,T,URL,[])
P at URL if Body  -->  P :- taxlogBody(Body,_,URL,[])
*/

taxlog2prolog(if(function(Call,Result),Body), neck(if)-[delimiter-[head(meta,Call),classify],SpecB], (function(Call,Result):-Body)) :- !,
    taxlogBodySpec(Body,SpecB).
taxlog2prolog(if(at(on(H,T),Url),B), neck(if)-[delimiter-[delimiter-[SpecH,classify],classify],SpecB], (H:-taxlogBody(B,T,Url,[]))) :- !,
    taxlogHeadSpec(H,SpecH), taxlogBodySpec(B,SpecB).
taxlog2prolog(if(at(H,Url),B), neck(if)-[delimiter-[SpecH,classify],SpecB], (H:-taxlogBody(B,_T,Url,[]))) :- !,
    taxlogHeadSpec(H,SpecH), taxlogBodySpec(B,SpecB).
taxlog2prolog(if(on(H,T),B), neck(if)-[delimiter-[SpecH,classify],SpecB], (H:-taxlogBody(B,T,'',[]))) :- !,
    taxlogHeadSpec(H,SpecH), taxlogBodySpec(B,SpecB).
taxlog2prolog(if(H,B),neck(if)-[SpecH,SpecB],(H:-taxlogBody(B,_,'',[]))) :- !,
    taxlogHeadSpec(H,SpecH), taxlogBodySpec(B,SpecB).
taxlog2prolog((because(on(H,T),Why):-B), neck(clause)-[ delimiter-[delimiter-[SpecH,classify],classify], SpecB ], (H:-taxlogBody(B,T,'',Why))) :- Why\==[], !,
    taxlogHeadSpec(H,SpecH), taxlogBodySpec(B,SpecB).
taxlog2prolog(mainGoal(G,Description),delimiter-[Spec,classify],(mainGoal(G,Description):-(_=1->true;GG))) :- !, % hack to avoid 'unreferenced' highlight in SWISH
    functor(G,F,N), functor(GG,F,N), % avoid "Singleton-marked variable appears more than once"
    taxlogBodySpec(G,Spec).
taxlog2prolog(example(T,Sequence),delimiter-[classify,Spec],example(T,Sequence)) :- !,  
    (Sequence==[]->Spec=classify ; (Spec=list-SeqSpec, scenarioSequenceSpec(Sequence,SeqSpec))).
taxlog2prolog(irrelevant_explanation(G),delimiter-[Spec],irrelevant_explanation(G)) :- !, 
    taxlogBodySpec(G,Spec).

scenarioSequenceSpec([S|Scenarios],[Spec|Specs]) :- !,
    scenarioSpec(S,Spec),
    scenarioSequenceSpec(Scenarios,Specs).
scenarioSequenceSpec([],[]).

scenarioSpec(scenario(Facts,Assertion),delimiter-[FactsSpec,Spec]) :- 
    (Facts==[] -> FactsSpec=classify ; (factsSpecs(Facts,FS), FactsSpec=list-FS)),
    taxlogBodySpec(Assertion,Spec).

factsSpecs([Fact_|Facts],[FactSpec|Specs]) :- !,  
    (Fact_= -Fact -> FactSpec= delimiter-[FS] ; (Fact=Fact_,FactSpec=FS)),
    (taxlog2prolog(Fact,FS,_)->true;taxlogHeadSpec(Fact,FS)), 
    factsSpecs(Facts,Specs).
factsSpecs([],[]).

taxlogHeadSpec(H,head(Class, H)) :- current_source(UUID),
    !,
    xref_module(UUID,Me),
    (H=on(RealH,_T)->true;H=RealH),
    (xref_called(_Other,Me:RealH, _) -> (Class=exported) ;
        xref_called(UUID, RealH, _By) -> (Class=head) ;
        Class=unreferenced).
taxlogHeadSpec(H,head(head, H)).

:- multifile swish_highlight:style/3.
swish_highlight:style(neck(if),     neck, [ text(if) ]).

% :- thread_local current_module/1.
% :- multifile prolog_colour:directive_colours/2.
% prolog_colour:directive_colours((:- module(M,_)),null) :-
%     mylog(detected_module/M), % NOT CALLED AT ALL???
%     retractall(current_module(_)), assert(current_module(M)), fail.


% this must be in sync with the interpreter i(...) and prolog:meta_goal(...) hooks
taxlogBodySpec(V,classify) :- var(V), !.
taxlogBodySpec(and(A,B),delimiter-[SpecA,SpecB]) :- !, 
    taxlogBodySpec(A,SpecA), taxlogBodySpec(B,SpecB).
taxlogBodySpec((A,B),delimiter-[SpecA,SpecB]) :- !, 
    taxlogBodySpec(A,SpecA), taxlogBodySpec(B,SpecB).
taxlogBodySpec(or(A,B),delimiter-[SpecA,SpecB]) :- !, 
    taxlogBodySpec(A,SpecA), taxlogBodySpec(B,SpecB).
taxlogBodySpec((A;B),delimiter-[SpecA,SpecB]) :- !, 
    taxlogBodySpec(A,SpecA), taxlogBodySpec(B,SpecB).
taxlogBodySpec(must(if(I),M),delimiter-[delimiter-SpecI,SpecM]) :- !, 
    taxlogBodySpec(I,SpecI), taxlogBodySpec(M,SpecM).
taxlogBodySpec(not(G),delimiter-[Spec]) :- !, 
    taxlogBodySpec(G,Spec).
taxlogBodySpec((\+G),delimiter-[Spec]) :- !, 
    taxlogBodySpec(G,Spec).
taxlogBodySpec(then(if(C),else(T,Else)),delimiter-[delimiter-[SpecC],delimiter-[SpecT,SpecE]]) :- !, 
    taxlogBodySpec(C,SpecC), taxlogBodySpec(T,SpecT), taxlogBodySpec(Else,SpecE).
taxlogBodySpec(then(if(C),Then),delimiter-[delimiter-[SpecC],SpecT]) :- !, 
    taxlogBodySpec(C,SpecC), taxlogBodySpec(Then,SpecT).
taxlogBodySpec(forall(C,Must),control-[SpecC,SpecMust]) :- !, 
    taxlogBodySpec(C,SpecC), taxlogBodySpec(Must,SpecMust).
taxlogBodySpec(setof(_X,G,_L),control-[classify,SpecG,classify]) :- !, 
    taxlogBodySpec(G,SpecG). 
taxlogBodySpec(bagof(_X,G,_L),control-[classify,SpecG,classify]) :- !, 
    taxlogBodySpec(G,SpecG). 
taxlogBodySpec(_^G,delimiter-[classify,SpecG]) :- !,
    taxlogBodySpec(G,SpecG).
% this is needed only to deal with multiline instances of aggregate... (or of any predicate of our own colouring, apparently:-( )
taxlogBodySpec(aggregate(_X,G,_L),control-[classify,SpecG,classify]) :- !, 
    taxlogBodySpec(G,SpecG). 
taxlogBodySpec(findall(_X,G,_L),control-[classify,SpecG,classify]) :- !, 
    taxlogBodySpec(G,SpecG). 
taxlogBodySpec(question(_,_),delimiter-[classify,classify]). % to avoid multiline colouring bug
taxlogBodySpec(question(_),delimiter-[classify]).
taxlogBodySpec(M:G,delimiter-[classify,SpecG]) :- !, taxlogBodySpec(at(G,M),delimiter-[SpecG,classify]).
taxlogBodySpec(at(G_,M_),Spec) :- nonvar(M_), nonvar(G_), !, % assuming atomic goals
    atom_string(M,M_), %TODO: this might be cleaned up/refactored with the next clauses:
    (G_=on(G,_) -> Spec=delimiter-[delimiter-[SpecG,classify],classify]; (G=G_, Spec=delimiter-[SpecG,classify])),
    (my_xref_defined(M,G,_)-> SpecG=goal(imported(M),G) ; SpecG=goal(undefined,G)).
taxlogBodySpec(on(G,_T),delimiter-[SpecG,classify] ) :- !,
    taxlogBodySpec(G,SpecG).
taxlogBodySpec(G,Spec) :-  
    (compound(G)->Spec=goal(Class,G)-classify;Spec=goal(Class,G)), current_source(UUID), taxlogGoalSpec(G, UUID, Class),
    !. 
taxlogBodySpec(_G,classify).

taxlogGoalSpec(G, UUID, Class) :-
    (my_xref_defined(UUID, G, Class) -> true ; 
        %prolog_colour:built_in_predicate(G)->Class=built_in ;
        my_goal_classification(G,Class) -> true;
        Class=undefined).

:- if(current_prolog_flag(version_data,swi(8, 2, _, _))).
my_goal_classification(G,Class) :-
    prolog_colour:call_goal_classification(G, Class).
:- elif(( current_prolog_flag(version_data,V), V@>= swi(8, 3, 0, []))).
my_goal_classification(G,Class) :-
    prolog_colour:call_goal_classification(G, _Module, Class).
:- else.
:- print_message(error,"You need SWI-Prolog 8.2 or later"-[]), halt(1).
:- endif.

my_xref_defined(M,G,Class) :- % check that the source has already been xref'ed, otherwise xref would try to load it and cause a "iri_scheme" error:
    xref_current_source(M), xref_defined(M,G,Class).

:- if(current_module(swish)). %%% only when running with the SWISH web server:
% hack to find the editor (e.g. its module name) that triggered the present highlighting
current_source(UUID) :- 
    swish_highlight:current_editor(UUID, _TB, source, Lock, _), mutex_property(Lock,status(locked(_Owner, _Count))), !.
current_source(UUID) :- 
    %mylog('Could not find locked editor, going with the first one'), 
    swish_highlight:current_editor(UUID, _TB, source, _Lock, _), !.

:- else. %% barebones SWI-Prolog:
% find the module in the file being coloured (which has been xref'd already)
current_source(Source) :- 
    prolog_load_context(source,File), kp_location(Source,File,false).
:- endif.

