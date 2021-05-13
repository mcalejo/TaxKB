:- module(le2taxlog, [contract/3]).
:- thread_local predicate/3, action/3, error_at/2, dict/3.
:- discontiguous statement/3, declaration/4, predicate/3, action/3.

contract(FullText, In, Out) :-
    settings(Rules, Settings, In, Next),
    RulesforErrors =
      [(predicate(_, Pos, _R1)
         :- asserterror('Found no predicate at', Pos), fail)],
    append(Rules, RulesforErrors, MRules),
    assertall(MRules), % asserting parsing rules for predicates and actions
    rules_previous(Next, NextNext), 
    content(Content, NextNext, Out), append(Settings, Content, FullText).
  %contract(_,_,_) :- showerror, fail.
  
  settings(AllR, AllS) --> declaration(Rules,Setting), settings(RRules, RS),
      {append(Setting, RS, AllS),
     append(Rules, RRules, AllR)}.
  settings([],[]) --> [].
  
  content(C) --> statement(S), content(R), {append(S,R,C)}.
  content([]) --> [].


declaration(Rules, [predicates(Fluents)]) -->
    predicate_previous, list_of_predicates_decl(Rules, Fluents).

predicate_previous --> [the, predicates, are, ':'].

rules_previous --> [the, rules, are, ':']. 

list_of_predicates_decl([Ru|R1], [F|R2]) --> predicate_decl(Ru,F), list_of_predicates_decl(R1,R2).
list_of_predicates_decl([],[]) --> [].

% a first person has a balance, 
% action(lambda([S,O],create(S,O))) --> [creates].
% fluent(lambda([Arg1,Arg2],voteCount(Arg1,Arg2))) --> [has].

predicate_decl(dict([Predicate|Arguments],TypesAndNames, Template), Relation) -->
    template_decl(RawTemplate), comma_or_period, 
    {build_template(RawTemplate, Predicate, Arguments, TypesAndNames, Template),
     Relation =.. [Predicate|Arguments]}.

template_decl([Word|RestW], [Word|RestIn], Out) :-
    not(lists:member(Word,[the, '.', ','])),
    template_decl(RestW, RestIn, Out).
template_decl([], [Word|Rest], [Word|Rest]) :-
    lists:member(Word,[the, '.', ',']). 

build_template(RawTemplate, Predicate, Arguments, TypesAndNames, Template) :-
    template_elements(RawTemplate, Arguments, TypesAndNames, OtherWords, Template),
    name_predicate(OtherWords, Predicate).

template_elements([], [], [], [], []).     
template_elements([Word|RestofWords], [Var|RestVars], [Name-Type|RestTypes], Others, [Var|RestTemplate]) :-
    ind_det(Word), 
    extract_variable(RestofWords, Var, NameWords, Type, NextWords),
    name_predicate(NameWords, Name), 
    template_elements(NextWords, RestVars, RestTypes, Others, RestTemplate).
template_elements([Word|RestofWords], RestVars, RestTypes,  [Word|Others], [Word|RestTemplate]) :-
    template_elements(RestofWords, RestVars, RestTypes, Others, RestTemplate).

extract_variable([Word|RestofWords], Var, [Word|RestName], Type, NextWords) :-
    ordinal(_, Word),
    extract_variable(RestofWords, Var, RestName, Type, NextWords).
extract_variable([Word|RestofWords], _, [Word], Word, RestofWords) :-
    is_a_type(Word).

name_predicate(Words, Predicate) :-
    concat_atom(Words, '_', Predicate). 

statement([Prolog]) --> prolog_fact(Prolog).

prolog_fact(Prolog) -->  % binary predicate
    t_or_w(X, [], M2), word(Predicate), t_or_w(Y, M2, _M_Out), period,
    {Prolog =.. [Predicate, X, Y]}.

statement([if(Head,Conditions)]) -->
    literal([], Map1, Head), if_, conjunction(Map1, _, Conditions), period.

%
conjunction(Map1, Map2, [C|CC]) --> literal(Map1, Map3, C),
   and_, conjunction(Map3, Map2, CC).
conjunction(Map1, Map2, [C]) --> literal(Map1, Map2, C).

literal(Map1, Map1, Literal) --> 
    predicate_statement(PossibleTemplate),
    {match_template(PossibleTemplate, Literal)}.

predicate_statement([Word|RestW], [Word|RestIn], Out) :-
    not(lists:member(Word,[if, and, or, '.'])),
    predicate_statement(RestW, RestIn, Out).
predicate_statement([], [Word|Rest], [Word|Rest]) :-
    lists:member(Word,[if, and, or, '.']). 

match_template(PossibleTemplate, Literal) :-
    rebuild_template(PossibleTemplate, Template),
    dict(Predicate, _, Template),
    Literal =.. Predicate. 

rebuild_template(RawTemplate, Template) :-
    template_elements(RawTemplate, Template).

template_elements([], []).     
template_elements([Word|RestofWords], [Var|RestTemplate]) :-
    (ind_det(Word); def_det(Word)), 
    extract_variable(RestofWords, Var, _, _, NextWords),
    template_elements(NextWords, RestTemplate).
template_elements([Word|RestofWords],[Word|RestTemplate]) :-
    template_elements(RestofWords, RestTemplate).

% a voter votes for a first candidate in a ballot
% the voter votes for a second candidate in the ballot at..
%literal(M_In,M_Out, happens(Action, T1, T2)) -->
%    t_or_w(X, M_In, M2), action(lambda([X,Y,B], Action)), for,
%    t_or_w(Y, M2, M3), in, t_or_w(B, M3, M4),
%    mapped_time_expression([T1,T2], M4, M_Out).

if_ --> [if].

period --> ['.'].
comma --> [','].
comma_or_period --> period, !.
comma_or_period --> comma. 

and_ --> [and].

%mapped_time_expression([T1,T2], Mi, Mo) -->
%    from_, t_or_w(T1, Mi, M2), to_, t_or_w(T2, M2, Mo).
% mapped_time_expression([_T0,T], Mi, Mo) -->
 %   at_, t_or_w(T, Mi, Mo).


/* --------------------------------------------------------- Utils in Prolog */
ordinal(1,  'first').
ordinal(2,  'second').
ordinal(3,  'third').
ordinal(4,  'fourth').
ordinal(5,  'fifth').
ordinal(6,  'sixth').
ordinal(7,  'seventh').
ordinal(8,  'eighth').
ordinal(9,  'ninth').
ordinal(10, 'tenth').

% if it is a type is not a word. Using cut
t_or_w(S, InMap, OutMap, In, Out) :- type(S, InMap, OutMap, In, Out), !.
t_or_w(W, Map, Map, In, Out) :- word(W, In, Out).

% treating a list as one word for simplicity
word(L, ['['|R], RR) :- rebuilt_list(R, [], L, RR).
       % append(L, [']'|RR], R). % append(['['|W], [']'], L), !.
word(W, [P1, '_', P2|R], R) :- atomic_list_concat([P1, '_', P2], '', W), !.
word(W, [P1, '_', P2, '_', P3|R], R) :-
  atomic_list_concat([P1, '_', P2, '_', P3], '', W), !.
word(W, [W|R], R)  :- not(reserved_word(W)).
word(_, Pos, _) :- asserterror('No word at ', Pos), fail.

rebuilt_list([']'|RR], In, In, RR) :- !. % only the first ocurrence
rebuilt_list([','|RR], In, Out, NRR) :- !,
   rebuilt_list(RR, In, Out, NRR).
rebuilt_list([A|RR], In, [A|Out], NRR) :-
   rebuilt_list(RR, In, Out, NRR).

% 0 votes
type(N, Map, Map, [N, Type|Out], Out) :-
   number(N), is_a_type(Type).
% a number of votes
type(V, InMap,OutMap, [D, number, of, Type|Out], Out) :-
   ind_det(D),
   atomic_concat(number, Type, VarName),
   OutMap = [map(V,VarName)|InMap], !.
% "the number of votes" is a special case of anaphora
type(V, InMap,OutMap, [the, number, of, Type|Out], Out) :-
   atomic_concat(number, Type, VarName),
   ((member(map(V,VarName),InMap), OutMap = InMap);
    OutMap = [map(V,VarName)|InMap]), !.
type(V, InMap,OutMap, [D, Ordinal, Type|Out], Out) :-
   ind_det(D),
   ordinal(_, Ordinal),
   atomic_concat(Ordinal, Type, VarName),
   OutMap = [map(V,VarName)|InMap], !.
type(V, InMap,InMap, [the, Ordinal, Type|Out], Out) :-
   ordinal(_, Ordinal),
   atomic_concat(Ordinal, Type, VarName),
   member(map(V,VarName),InMap), !.
type(V, InMap,OutMap, [the, Ordinal, Type|Out], Out) :-
   ordinal(_, Ordinal),
   atomic_concat(Ordinal, Type, VarName),
   not(member(map(V, VarName), InMap)),
   OutMap = [map(V,VarName)|InMap]. % creates the var if it does not exist
type(V, InMap,OutMap, [D,Type|Out], Out) :- ind_det(D), OutMap = [map(V,Type)|InMap].
type(V, InMap,InMap, [the,Type|Out], Out) :- member(map(V,Type),InMap).
type(V, InMap,OutMap, [the,Type|Out], Out) :-  OutMap = [map(V,Type)|InMap]. % creates the var if it does not exist
type(_, In, In, Pos, _) :- asserterror('No type at ', Pos), fail.

is_a_type(T) :- % pending integration with wei2nlen:is_a_type/1
   atom(T),
   not(number(T)), not(punctuation(T)),
   not(reserved_word(T)).

ind_det(a).
ind_det(an).
ind_det(some).

def_det(the).

reserved_word(W) :- % more reserved words pending
  punctuation(W);
  W = 'is'; W ='not'; W='When'; W='when'; W='if'; W='If'; W='then';
  W = 'at'; W= 'from'; W='to'; W='and'; W='half'.

punctuation('.').
punctuation(',').
punctuation(';').
punctuation(':').

assertall([]).
assertall([F|R]) :-
    not(asserted(F)),
    assertz(F), !,
    % write('Asserting .. '), write(F), nl, nl,
    assertall(R).
assertall([_F|R]) :-
    % write(' Already there .. '), write(F), nl,
    assertall(R).

asserted(F :- B) :- clause(F, B). % as a rule with a body
asserted(F) :- clause(F,true). % as a fact

asserterror(Me, Pos) :-
   % (clause(error_at(_,_), _) -> retractall(error_at(_,_));true),
   asserta(error_at(Me, Pos)).

showerror.

first_words([W1,W2,W3], [W1,W2,W3|R],R).
%first_words([W1,W2], [W1,W2|R],R).
%first_words([W1], [W1|R],R).

%   (clause(error_at(Me,Pos), _) ->
%        ( nl, nl, write('Error: '), writeq(Me), writeq(Pos), nl, nl)
%    ; nl, nl, writeln('No error reported')).

spypoint(A,A). % for debugging more easily
