:- module(le_to_taxlog, [document/3]).
:- use_module('./tokenize/prolog/tokenize.pl').
:- thread_local literal/5, text_size/1, notice/3, dict/3.
:- discontiguous statement/3, declaration/4, predicate/3, action/3.

% Main clause: text_to_logic(+String,-Errors,-Clauses) is det
text_to_logic(String, Error, Translation) :-
    tokenize(String, Tokens, [cased(true), spaces(true)]),
    unpack_tokens(Tokens, UTokens), 
    clean_comments(UTokens, CTokens), 
    write(CTokens), 
    ( phrase(document(Translation), CTokens) -> 
        Error=[]
    ;   ( showerror(Output), explain_error(String, Output, Error), Translation=[])). 

% document(-Translation, In, Rest)
% a DCG predicate to translate a LE document into Taxlog prolog terms
document(Translation, In, Rest) :-
    header(Settings, In, Next), 
    spaces_or_newlines(_, Next, Intermediate),
    rules_previous(Intermediate, NextNext), 
    content(Content, NextNext, Rest), append(Settings, Content, Translation).

header(Settings, In, Next) :-
    length(In, TextSize), 
    ( settings(Rules, Settings, In, Next) -> true
    ; (Rules = [], Settings = [])),
    RulesforErrors = % rules for error have been statically added
      [(text_size(TextSize))],
    append(Rules, RulesforErrors, MRules),
    assertall(MRules). % asserting contextual information

/* --------------------------------------------------------- LE DCGs */

settings(AllR, AllS) --> declaration(Rules,Setting), settings(RRules, RS),
      {append(Setting, RS, AllS),
     append(Rules, RRules, AllR)}.
settings([],[]) --> [].
  
content(C) --> 
    spaces_or_newlines(_), 
    statement(S), 
    spaces_or_newlines(_), 
    content(R), 
    spaces_or_newlines(_), {append(S,R,C)}.
content([]) --> [].

declaration(Rules, [predicates(Fluents)]) -->
    predicate_previous, list_of_predicates_decl(Rules, Fluents).

predicate_previous --> 
    spaces(_), [the], spaces(_), [predicates], spaces(_), [are], spaces(_), [':'], spaces(_), ['\n'].

list_of_predicates_decl([Ru|R1], [F|R2]) --> predicate_decl(Ru,F), rest_list_of_predicates_decl(R1,R2).

rules_previous --> 
    spaces(_), [the], spaces(_), [rules], spaces(_), [are], spaces(_), [':'], spaces(_), ['\n'].

rest_list_of_predicates_decl(L1, L2) --> comma, list_of_predicates_decl(L1, L2).
rest_list_of_predicates_decl([],[]) --> period.

predicate_decl(dict([Predicate|Arguments],TypesAndNames, Template), Relation) -->
    spaces(_), template_decl(RawTemplate), 
    {build_template(RawTemplate, Predicate, Arguments, TypesAndNames, Template),
     Relation =.. [Predicate|Arguments]}.
% error clause
predicate_decl(_, _, Rest, _R1) :- 
    text_size(Size), length(Rest, Rsize), Pos is Size - Rsize, 
    asserterror('Syntax error found in a declaration at position ', Pos), fail.

% statement: the different types of statements in a LE text
statement([if(Head,Conditions)]) -->
    literal([], Map1, Head), newline,
    spaces(Ind), if_, conditions(Ind, Map1, _MapN, ListOfConds), 
    {map_to_conds(ListOfConds, Conditions)}, spaces_or_newlines(_), period, !. % <- cut !!!!

literal(Map1, MapN, Literal) --> 
    predicate_template(PossibleTemplate),
    {match_template(PossibleTemplate, Map1, MapN, Literal)}.
% error clause
literal(M, M, _, Rest, _R1) :- 
    text_size(Size), length(Rest, Rsize), Pos is Size - Rsize, 
    asserterror('Syntax error found in a literal at position ', Pos), fail.

% regular and/or lists of conditions
conditions(Ind0, Map1, MapN, [Op-Ind-Cond|RestC]) --> 
    condition(Cond, Ind0, Map1, Map2), 
    more_conds(Ind0, Ind, Map2, MapN, Op, RestC).

more_conds(_, Ind, Map2, MapN, Op, RestC) --> 
    newline, spaces(Ind), 
    operator(Op), % Op are and, or. 
    conditions(Ind,Map2, MapN, RestC). 
more_conds(Ind, Ind, Map, Map, last, []) --> []. 
 
term(Term, Map1, MapN) --> variable(Term, Map1, MapN); constant(Term, Map1, MapN); le_list(Term, Map1, MapN). 

expression((X - Y), Map1, MapN) --> 
    term(X, Map1, Map2), spaces(_), minus_, spaces(_), expression(Y, Map2, MapN), spaces(_). 
expression((X + Y), Map1, MapN) --> 
    term(X, Map1, Map2), spaces(_), plus_, spaces(_), expression(Y, Map2, MapN), spaces(_). 
expression(Y, Map1, MapN) --> 
    term(Y, Map1, MapN), spaces(_).

% the Value is the sum of each Asset Net such that
condition(FinalExpression, _, Map1, MapN) --> 
    variable(Value, Map1, Map2), is_the_sum_of_each_, extract_variable(Each, NameWords, _), such_that_, !, 
    spaces(_), { name_predicate(NameWords, Name), update_map(Each, Name, Map2, Map3) }, newline, 
    spaces(Ind), conditions(Ind, Map3, Map4, ListOfConds), {map_to_conds(ListOfConds, Conds)},
    modifiers(aggregate_all(sum(Each),Conds,Value), Map4, MapN, FinalExpression).
    
% it is not the case that: 
condition(not(Conds), _, Map1, MapN) --> 
    spaces(_), not_, newline, !, 
    spaces(Ind), conditions(Ind, Map1, MapN, ListOfConds), {map_to_conds(ListOfConds, Conds)}.

condition(Cond, _, Map1, MapN) -->
    literal(Map1, MapN, Cond), !. 

% condition(-Cond, ?Ind, +InMap, -OutMap)
condition(InfixBuiltIn, _, Map1, MapN) --> 
    term(Term, Map1, Map2), spaces(_), builtin_(BuiltIn), 
    spaces(_), expression(Expression, Map2, MapN), {InfixBuiltIn =.. [BuiltIn, Term, Expression]}. 

% error clause
condition(_, _Ind, Map, Map, Rest, _R1) :- 
        text_size(Size), length(Rest, Rsize), Pos is Size - Rsize, 
        asserterror('Syntax error found at a condition at position ', Pos), fail.

% modifiers add reifying predicates to an expression. 
% modifiers(+MainExpression, +MapIn, -MapOut, -FinalExpression)
modifiers(MainExpression, Map1, MapN, on(MainExpression, Var) ) -->
    newline, spaces(_), at_, variable(Var, Map1, MapN). % newline before a reifying expression
modifiers(MainExpression, Map, Map, MainExpression) --> [].  

variable(Var, Map1, MapN) --> 
    spaces(_), [Det], {determiner(Det)}, extract_variable(Var, NameWords, _),
    { name_predicate(NameWords, Name), update_map(Var, Name, Map1, MapN) }. 

constant(Constant, Map, Map) -->
    extract_constant(NameWords), { name_predicate(NameWords, Constant) }.

le_list(Constant, Map1, MapN) --> 
    spaces(_), bracket_open_,   
    extract_list(NameWords, Map1, MapN), { name_predicate(NameWords, Constant) }.

spaces(N) --> [' '], !, spaces(M), {N is M + 1}.
spaces(N) --> ['\t'], !, spaces(M), {N is M + 1}. % counting tab as one space
spaces(0) --> []. 

spaces_or_newlines(N) --> [' '], !, spaces_or_newlines(M), {N is M + 1}.
spaces_or_newlines(N) --> ['\t'], !, spaces_or_newlines(M), {N is M + 1}. % counting tab as one space
spaces_or_newlines(N) --> ['\r'], !, spaces_or_newlines(M), {N is M + 1}. % counting \r as one space
spaces_or_newlines(N) --> ['\n'], !, spaces_or_newlines(M), {N is M + 1}. % counting \n as one space
spaces_or_newlines(0) --> [].

newline --> ['\n'].
newline --> ['\r'].

if_ --> [if].

period --> ['.'].
comma --> [','].

comma_or_period --> period, !, ['\n'].
comma_or_period --> period, !.
comma_or_period --> comma, !, ['\n']. 
comma_or_period --> comma. 

and_ --> [and].

or_ --> [or].

not_ --> [it], spaces(_), [is], spaces(_), [not], spaces(_), [the], spaces(_), [case], spaces(_), [that], spaces(_). 

is_the_sum_of_each_ --> [is], spaces(_), [the], spaces(_), [sum], spaces(_), [of], spaces(_), [each], spaces(_) .

such_that_ --> [such], spaces(_), [that], spaces(_). 

at_ --> [at], spaces(_). 

minus_ --> ['-'], spaces(_).

plus_ --> ['+'], spaces(_).

divide_ --> ['/'], spaces(_).

times_ --> ['*'], spaces(_).

bracket_open_ --> ['['], spaces(_). 

/* --------------------------------------------------- Supporting code */
clean_comments([], []) :- !.
clean_comments(['%'|Rest], New) :- % like in prolog comments start with %
    jump_comment(Rest, Next), 
    clean_comments(Next, New). 
clean_comments([Code|Rest], [Code|New]) :-
    clean_comments(Rest, New).

jump_comment([], []).
jump_comment(['\n'|Rest], ['\n'|Rest]). % leaving the end of line in place
jump_comment([_|R1], R2) :-
    jump_comment(R1, R2). 

% cuts added to improve efficiency
template_decl(RestW, [' '|RestIn], Out) :- !, % skip spaces in template
    template_decl(RestW, RestIn, Out).
template_decl(RestW, ['\t'|RestIn], Out) :- !, % skip cntrl \t in template
    template_decl(RestW, RestIn, Out).
template_decl(RestW, ['\n'|RestIn], Out) :- !, % skip cntrl \n in template
    template_decl(RestW, RestIn, Out).
template_decl(RestW, ['\r'|RestIn], Out) :- !, % skip cntrl \r in template
    template_decl(RestW, RestIn, Out).
template_decl([Word|RestW], [Word|RestIn], Out) :-
    not(lists:member(Word,['.', ','])), !,  % only . and , as boundaries. Beware!
    template_decl(RestW, RestIn, Out).
template_decl([], [Word|Rest], [Word|Rest]) :-
    lists:member(Word,['.', ',']). 

build_template(RawTemplate, Predicate, Arguments, TypesAndNames, Template) :-
    build_template_elements(RawTemplate, [], Arguments, TypesAndNames, OtherWords, Template),
    name_predicate(OtherWords, Predicate).

% build_template_elements(+Input, +Previous, -Args, -TypesNames, -OtherWords, -Template)
build_template_elements([], _, [], [], [], []).     
build_template_elements([Word|RestOfWords], Previous, [Var|RestVars], [Name-Type|RestTypes], Others, [Var|RestTemplate]) :-
    (ind_det(Word); ind_det_C(Word)), Previous \= [is|_], 
    extract_variable(Var, NameWords, TypeWords, RestOfWords, NextWords),
    name_predicate(NameWords, Name), 
    name_predicate(TypeWords, Type), 
    build_template_elements(NextWords, [], RestVars, RestTypes, Others, RestTemplate).
build_template_elements([Word|RestOfWords], Previous, RestVars, RestTypes,  [Word|Others], [Word|RestTemplate]) :-
    build_template_elements(RestOfWords, [Word|Previous], RestVars, RestTypes, Others, RestTemplate).

% extract_variable(-Var, -ListOfNameWords, -ListOfTypeWords, +ListOfWords, -NextWordsInText)
% refactored as a dcg predicate
extract_variable(_, [], [], [], []) :- !.                                % stop at when words run out
extract_variable(_, [], [], [Word|RestOfWords], [Word|RestOfWords]) :-   % stop at reserved words, verbs or prepositions. 
    (reserved_word(Word); verb(Word); preposition(Word); punctuation(Word); phrase(newline, [Word])), !.  % or punctuation
extract_variable(Var, RestName, RestType, [' '|RestOfWords], NextWords) :- !, % skipping spaces
    extract_variable(Var, RestName, RestType, RestOfWords, NextWords).
extract_variable(Var, RestName, RestType, ['\t'|RestOfWords], NextWords) :- !,  % skipping spaces
    extract_variable(Var, RestName, RestType, RestOfWords, NextWords).  
extract_variable(Var, [Word|RestName], Type, [Word|RestOfWords], NextWords) :- % ordinals are not part of the name
    ordinal(Word), !, 
    extract_variable(Var, RestName, Type, RestOfWords, NextWords).
extract_variable(Var, [Word|RestName], [Word|RestType], [Word|RestOfWords], NextWords) :-
    is_a_type(Word),
    extract_variable(Var, RestName, RestType, RestOfWords, NextWords).

name_predicate(Words, Predicate) :-
    concat_atom(Words, '_', Predicate). 

% map_to_conds(+ListOfConds, -LogicallyOrderedConditions)
% the last condition always fits in
map_to_conds([last-_-C1], C1) :- !.   
map_to_conds([and-_-C1, last-_-C2], (C1,C2)) :- !. 
map_to_conds([or-_-C1, last-_-C2], (C1;C2)) :- !.
% from and to and
map_to_conds([and-Ind-C1, and-Ind-C2|RestC], (C1, C2, RestMapped) ) :- !, 
    map_to_conds(RestC, RestMapped).
% from or to ord
map_to_conds([or-Ind-C1, or-Ind-C2|RestC], (C1; C2; RestMapped) ) :- !, 
    map_to_conds(RestC, RestMapped).
% from and to deeper or
map_to_conds([and-Ind1-C1, or-Ind2-C2|RestC], (C1, (C2; RestMapped)) ) :-  
    Ind1 < Ind2, !, 
    map_to_conds(RestC, RestMapped).
% from deeper or to and
map_to_conds([or-Ind1-C1, and-Ind2-C2|RestC], ((C1; C2), RestMapped) ) :-
    Ind1 > Ind2, !, 
    map_to_conds([and-Ind2-C2|RestC], RestMapped).
% from or to deeper and
map_to_conds([or-Ind1-C1, and-Ind2-C2|RestC], (C1; (C2, RestMapped)) ) :-
    Ind1 < Ind2, !, 
    map_to_conds(RestC, RestMapped).
% from deeper and to or
map_to_conds([and-Ind1-C1, or-Ind2-C2|RestC], ((C1, C2);RestMapped ) ) :-
    Ind1 > Ind2, 
    map_to_conds(RestC, RestMapped).

operator(and, In, Out) :- and_(In, Out).
operator(or, In, Out) :- or_(In, Out).

% cuts added to improve efficiency
predicate_template(RestW, [' '|RestIn], Out) :-  !, % skip spaces in template
    predicate_template(RestW, RestIn, Out).
predicate_template(RestW, ['\t'|RestIn], Out) :- !,  % skip tabs in template
    predicate_template(RestW, RestIn, Out).
predicate_template([Word|RestW], [Word|RestIn], Out) :-
    not(lists:member(Word,['\n', if, and, or, '.'])), !, 
    predicate_template(RestW, RestIn, Out).
predicate_template([], [Word|Rest], [Word|Rest]) :-
    lists:member(Word,['\n', if, and, or, '.']). 

match_template(PossibleLiteral, Map1, MapN, Literal) :-
    dict(Predicate, _, Candidate),
    match(Candidate, PossibleLiteral, Map1, MapN, Template), 
    dict(Predicate, _, Template),
    Literal =.. Predicate. 

% match(+CandidateTemplate, +PossibleLiteral, +MapIn, -MapOut, -SelectedTemplate)
match([], [], Map, Map, []). % success! It succeds iff PossibleLiteral is totally consumed
match([Element|RestElements], [Word|PossibleLiteral], Map1, MapN, [Element|RestSelected]) :-
    nonvar(Element), Word = Element, 
    match(RestElements, PossibleLiteral, Map1, MapN, RestSelected). 
match([Element|RestElements], [Det|PossibleLiteral], Map1, MapN, [Var|RestSelected]) :-
    var(Element), 
    determiner(Det), 
    % extract_variable(-Var, -ListOfNameWords, -ListOfTypeWords, ?ListOfWords, ?NextWordsInText)
    extract_variable(Var, NameWords, _, PossibleLiteral, NextWords),  NameWords \= [], % it is not empty % <- leave that _ unbound!
    name_predicate(NameWords, Name), 
    update_map(Var, Name, Map1, Map2),
    match(RestElements, NextWords, Map2, MapN, RestSelected).  
match([Element|RestElements], [Word|PossibleLiteral], Map1, MapN, [Constant|RestSelected]) :-
    var(Element), 
    extract_constant(NameWords, [Word|PossibleLiteral], NextWords), NameWords \= [], % it is not empty
    name_predicate(NameWords, Constant),
    update_map(Element, Constant, Map1, Map2),
    match(RestElements, NextWords, Map2, MapN, RestSelected). 
match([Element|RestElements], ['['|PossibleLiteral], Map1, MapN, [List|RestSelected]) :-
    var(Element), 
    extract_list(List, Map1, Map2, PossibleLiteral, NextWords),
    match(RestElements, NextWords, Map2, MapN, RestSelected). 

% extract_constant(ListOfNameWords, +ListOfWords, NextWordsInText)
extract_constant([], [], []) :- !.                                % stop at when words run out
extract_constant([], [Word|RestOfWords], [Word|RestOfWords]) :-   % stop at reserved words, verbs? or prepositions?. 
    (reserved_word(Word); verb(Word); preposition(Word); punctuation(Word); phrase(newline, [Word])), !.  % or punctuation
%extract_constant([Word|RestName], [Word|RestOfWords], NextWords) :- % ordinals are not part of the name
%    ordinal(Word), !,
%    extract_constant(RestName, RestOfWords, NextWords).
extract_constant(RestName, [' '|RestOfWords],  NextWords) :- !, % skipping spaces
    extract_constant(RestName, RestOfWords, NextWords).
extract_constant(RestName, ['\t'|RestOfWords],  NextWords) :- !, 
    extract_constant(RestName, RestOfWords, NextWords).
extract_constant([Word|RestName], [Word|RestOfWords],  NextWords) :-
    %is_a_type(Word),
    extract_constant(RestName, RestOfWords, NextWords).

% extract_list(-List, +Map1, -Map2, +[Word|PossibleLiteral], -NextWords),
extract_list([], Map, Map, [']'|Rest], Rest) :- !. 
extract_list(RestList, Map1, MapN, [' '|RestOfWords],  NextWords) :- !, % skipping spaces
    extract_list(RestList, Map1, MapN, RestOfWords, NextWords).
extract_list(RestList, Map1, MapN, ['\t'|RestOfWords],  NextWords) :- !, 
    extract_list(RestList, Map1, MapN, RestOfWords, NextWords).
extract_list(RestList, Map1, MapN, [','|RestOfWords],  NextWords) :- !, 
    extract_list(RestList, Map1, MapN, RestOfWords, NextWords).
extract_list([Var|RestList], Map1, MapN, [Det|InWords], LeftWords) :-
    determiner(Det), 
    extract_variable(Var, NameWords, _, InWords, NextWords), NameWords \= [], % <- leave that _ unbound!
    name_predicate(NameWords, Name),  !,
    update_map(Var, Name, Map1, Map2),
    extract_list(RestList, Map2, MapN, NextWords, LeftWords).
extract_list([Member|RestList], Map1, MapN, InWords, LeftWords) :-
    extract_constant(NameWords, InWords, NextWords), NameWords \= [],
    name_predicate(NameWords, Member),
    extract_list(RestList, Map1, MapN, NextWords, LeftWords).

determiner(Det) :-
    (ind_det(Det); ind_det_C(Det); def_det(Det); def_det_C(Det)), !. 

rebuild_template(RawTemplate, Map1, MapN, Template) :-
    template_elements(RawTemplate, Map1, MapN, [], Template).

% template_elements(+Input,+InMap, -OutMap, +Previous, -Template)
template_elements([], Map1, Map1, _, []).     
template_elements([Word|RestOfWords], Map1, MapN, Previous, [Var|RestTemplate]) :-
    (ind_det(Word); ind_det_C(Word)), Previous \= [is|_], 
    extract_variable(Var, NameWords, _, RestOfWords, NextWords),
    name_predicate(NameWords, Name), 
    update_map(Var, Name, Map1, Map2), 
    template_elements(NextWords, Map2, MapN, [], RestTemplate).
template_elements([Word|RestOfWords], Map1, MapN, Previous, [Var|RestTemplate]) :-
    (def_det_C(Word); def_det(Word)), Previous \= [is|_], 
    extract_variable(Var, NameWords, _, RestOfWords, NextWords),
    name_predicate(NameWords, Name), 
    member(map(Var,Name), Map1),  % confirming it is an existing variable and unifying
    template_elements(NextWords, Map1, MapN, [], RestTemplate).
template_elements([Word|RestOfWords], Map1, MapN, Previous, [Word|RestTemplate]) :-
    template_elements(RestOfWords, Map1, MapN, [Word|Previous], RestTemplate).

update_map(V, Name, InMap, InMap) :- % unify V with same named variable in current map
    member(map(V,Name),InMap), !.
update_map(V, Name, InMap, OutMap) :- % updates the map by adding a new variable into it. 
    OutMap = [map(V,Name)|InMap]. 

builtin_(BuiltIn, [BuiltIn1, BuiltIn2|RestWords], RestWords) :- 
    atom_concat(BuiltIn1, BuiltIn2, BuiltIn), 
    Predicate =.. [BuiltIn, _, _],  % only binaries fttb
    predicate_property(system:Predicate, built_in), !.
builtin_(BuiltIn, [BuiltIn|RestWords], RestWords) :- 
    Predicate =.. [BuiltIn, _, _],  % only binaries fttb
    predicate_property(system:Predicate, built_in). 

/* --------------------------------------------------------- Utils in Prolog */
unpack_tokens([], []).
unpack_tokens([First|Rest], [New|NewRest]) :-
    (First = word(New); First=cntrl(New); First=punct(New); 
     First=space(New); First=number(New); First=string(New)), !,
    unpack_tokens(Rest, NewRest).  

ordinal(Ord) :-
    ordinal(_, Ord). 

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

is_a_type(T) :- % pending integration with wei2nlen:is_a_type/1
   ground(T),
   not(number(T)), not(punctuation(T)),
   not(reserved_word(T)),
   not(verb(T)),
   not(preposition(T)). 

/* ------------------------------------------------ determiners */

ind_det_C('A').
ind_det_C('An').
% ind_det_C('Some').

def_det_C('The').

ind_det(a).
ind_det(an).
% ind_det(some).

def_det(the).

/* ------------------------------------------------ reserved words */
reserved_word(W) :- % more reserved words pending
    W = 'is'; W ='not'; W='if'; W='If'; W='then';
    W = 'at'; W= 'from'; W='to'; W='and'; W='half'; W='or'; 
    W = 'else'; W = 'otherwise'; 
    W = such ; 
    W = '<'; W = '='; W = '>'; W = '+'; W = '-'; W = '/'; W = '*';
    W = '{' ; W = '}' ; W = '(' ; W = ')' ; W = '[' ; W = ']';
    W = ':', W = ','; W = ';'.
reserved_word(P) :- punctuation(P).

/* ------------------------------------------------ punctuation */
%punctuation(punct(_P)).

punctuation('.').
punctuation(',').
punctuation(';').
punctuation(':').
punctuation('\'').

/* ------------------------------------------------ verbs */
verb(Verb) :- present_tense_verb(Verb); continuous_tense_verb(Verb); past_tense_verb(Verb). 

present_tense_verb(is).
present_tense_verb(occurs).
present_tense_verb(can).
present_tense_verb(qualifies).
present_tense_verb(has).
present_tense_verb(satisfies).
present_tense_verb(owns).
present_tense_verb(belongs).

continuous_tense_verb(according).

past_tense_verb(looked).
past_tense_verb(could).
past_tense_verb(had).
past_tense_verb(tried).
past_tense_verb(explained).
 
/* ------------------------------------------------- prepositions */
preposition(of).
preposition(on).
preposition(from).
preposition(to).
preposition(at).
preposition(in).
preposition(with).
preposition(plus).
preposition(as).

/* ------------------------------------------------- memory handling */
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

/* -------------------------------------------------- error handling */
asserterror(Me, Pos) :-
   (clause(notice(_,_,_), _) -> retractall(notice(_,_,_));true),
   asserta(notice(error, Me, Pos)).

showerror(Me-Pos) :-
   (clause(notice(error, Me,Pos), _) ->
        ( nl, nl, write('Error: '), writeq(Me), writeq(Pos), nl, nl)
    ; nl, nl, writeln('No error reported')).

explain_error(String, Me-Pos, Message) :-
    Start is Pos - 20, % assuming a window of 40 characters. 
    (Start>0 -> 
        ( sub_string(String,Start,40, _, Windows),
          sub_string(Windows, 0, 20, _, Left),
          sub_string(Windows, 20, 20, _, Right) )
    ;   ( sub_string(String,Pos,40, _, Windows), 
          Left = "", Right = Windows ) ),
    Message = [Me, at , Pos, near, ':', Left, '<-HERE->', Right]. 

spypoint(A,A). % for debugging

/* ------------------------------------------ producing readable taxlog code */
write_taxlog_code(Source, Readable) :-
    Source = [predicates(_)|Clauses],
    write_taxlog_clauses(Clauses, Readable).

write_taxlog_clauses([], []).
write_taxlog_clauses([If|RestClauses], [ReadableIf|RestReadable]) :-
    write_taxlog_if(If, ReadableIf),
    write_taxlog_clauses(RestClauses, RestReadable).

write_taxlog_if(Rule, if(ReadableHead, ReadableBody)) :-
    Rule = if(Head, Body),
    write_taxlog_literal(Head, ReadableHead, [], Map2),
    write_taxlog_body(Body, ReadableBody, Map2, _).

write_taxlog_literal(not(Body), not(ReadableLiteral), Map1, MapN) :- !, 
    write_taxlog_body(Body, ReadableLiteral, Map1, MapN). 

write_taxlog_literal(aggregate_all(sum(Each),Conds,Value), aggregate_all(sum(Each),NewConds,Value), Map1, MapN) :-
    write_taxlog_body(Conds, NewConds, Map1, MapN). 

write_taxlog_literal(InBuiltIn, OutBuiltIn, Map1, MapN) :-
    predicate_property(system:InBuiltIn, built_in),
    InBuiltIn =.. [Pred, Arg1, Arg2],
    (var(Arg1) -> (update_map(Arg1, Name1, Map1, Map2), NArg1 = Name1); NArg1 = Arg1),
    (var(Arg2) -> (update_map(Arg2, Name2, Map2, MapN), NArg2 = Name2); NArg2 = Arg2),
    OutBuiltIn =.. [Pred, NArg1, NArg2]. 

write_taxlog_literal(Literal, ReadableLiteral, Map1, MapN) :-
    Literal =.. [Pred|ArgVars],
    dict([Pred|ArgVars], Names, _),
    replace_varnames(ArgVars, Names, NewArgs, Map1, MapN),
    ReadableLiteral =.. [Pred|NewArgs].

replace_varnames([], [], [], Map, Map) :- !. 
replace_varnames([Var|RestVar], [VarName-_|RestVarNames], [Name|NewRest], Map1, MapN) :-
    var(Var),
    capitalize(VarName, Name), 
    update_map(Var, Name, Map1, Map2), 
    replace_varnames(RestVar, RestVarNames, NewRest, Map2, MapN). 
replace_varnames([V|RestVar], [_|RestVarNames], [V|NewRest], Map1, MapN) :-
    nonvar(V),
    replace_varnames(RestVar, RestVarNames, NewRest, Map1, MapN). 

% from drafter.pl
capitalize(X,NewX) :- 
    name(X,[First|Codes]), to_upper(First,U), name(NewX,[U|Codes]).

write_taxlog_body((A;B), or(NewA,NewB), Map1, MapN) :-
    write_taxlog_body(A, NewA, Map1, Map2),
    write_taxlog_body(B, NewB, Map2, MapN).

write_taxlog_body((A,B), and(NewA, NewB), Map1, MapN) :-
    write_taxlog_body(A, NewA, Map1, Map2),
    write_taxlog_body(B, NewB, Map2, MapN).

write_taxlog_body(Lit, Readable, Map1, MapN) :-
    write_taxlog_literal(Lit, Readable, Map1, MapN). 


%%% --------------------------------------------------- Interface to Formal english
%% based on logicalcontracts' lc_server.pl

:- multifile prolog_colour:term_colours/2.
prolog_colour:term_colours(en(_Text),lps_delimiter-[classify]). % let 'en' stand out with other taxlog keywords
prolog_colour:term_colours(en_decl(_Text),lps_delimiter-[classify]). % let 'en_decl' stand out with other taxlog keywords

user:le_taxlog_translate( en(Text), Terms) :- le_taxlog_translate( en(Text), Terms).

le_taxlog_translate( en(Text), Terms) :-
	%findall(Decl, psyntax:lps_swish_clause(en_decl(Decl),_Body,_Vars), Decls),
    %combine_list_into_string(Decls, StringDecl),
	%string_concat(StringDecl, Text, Whole_Text),
	% Can't print here, this was getting sent into a HTTP response...: writeq(Whole_Text),
    once( text_to_logic(Text, Error, Translation) ),
    (Translation=[]-> Terms=Error; Terms=Translation). 

combine_list_into_string(List, String) :-
    combine_list_into_string(List, "", String).

combine_list_into_string([], String, String).
combine_list_into_string([HS|RestS], Previous, OutS) :-
    string_concat(Previous, HS, NewS),
    combine_list_into_string(RestS, NewS, OutS).

user:showtaxlog :- showtaxlog.

showtaxlog:-
    % ?????????????????????????????????????????
	% psyntax:lps_swish_clause(en(Text),Body,_Vars),
	% (Body==true -> InternalTerm=H ; InternalTerm=(H:-Body)),
	%writeln(InternalTerm),
	once(text_to_logic(Text,Error,Taxlog)),
    writeln(Error), 
	writeln(Taxlog),
	fail.
showtaxlog.

sandbox:safe_primitive(le_to_taxlog:showtaxlog).
sandbox:safe_primitive(le_to_taxlog:le_taxlog_translate( _EnText, _Terms)).
