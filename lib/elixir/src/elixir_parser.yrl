Nonterminals
  grammar expr_list
  expr container_expr block_expr access_expr
  no_parens_expr no_parens_zero_expr no_parens_one_expr no_parens_one_ambig_expr
  bracket_expr bracket_at_expr bracket_arg matched_expr unmatched_expr max_expr
  unmatched_op_expr matched_op_expr no_parens_op_expr no_parens_many_expr
  comp_op_eol at_op_eol unary_op_eol and_op_eol or_op_eol capture_op_eol
  add_op_eol mult_op_eol two_op_eol three_op_eol pipe_op_eol stab_op_eol
  arrow_op_eol match_op_eol when_op_eol in_op_eol in_match_op_eol
  type_op_eol rel_op_eol
  open_paren close_paren empty_paren eoe
  list list_args open_bracket close_bracket
  tuple open_curly close_curly
  bit_string open_bit close_bit
  map map_op map_close map_args map_expr struct_op
  assoc_op_eol assoc_expr assoc_base assoc_update assoc_update_kw assoc
  container_args_base container_args
  call_args_parens_expr call_args_parens_base call_args_parens parens_call
  call_args_no_parens_one call_args_no_parens_ambig call_args_no_parens_expr
  call_args_no_parens_comma_expr call_args_no_parens_all call_args_no_parens_many
  call_args_no_parens_many_strict
  stab stab_eoe stab_expr stab_op_eol_and_expr stab_parens_many
  kw_eol kw_base kw call_args_no_parens_kw_expr call_args_no_parens_kw
  dot_op dot_alias dot_alias_container
  dot_identifier dot_op_identifier dot_do_identifier
  dot_paren_identifier dot_bracket_identifier
  do_block fn_eoe do_eoe end_eoe block_eoe block_item block_list
  number
  .

Terminals
  identifier kw_identifier kw_identifier_safe kw_identifier_unsafe bracket_identifier
  paren_identifier do_identifier block_identifier
  fn 'end' alias
  atom atom_safe atom_unsafe bin_string list_string sigil
  bin_heredoc list_heredoc
  dot_call_op op_identifier
  comp_op at_op unary_op and_op or_op arrow_op match_op in_op in_match_op
  type_op dual_op add_op mult_op two_op three_op pipe_op stab_op when_op assoc_op
  capture_op rel_op
  'true' 'false' 'nil' 'do' eol ';' ',' '.'
  '(' ')' '[' ']' '{' '}' '<<' '>>' '%{}' '%'
  int float
  .

Rootsymbol grammar.

%% Two shift/reduce conflicts coming from call_args_parens and
%% one coming from empty_paren on stab.
Expect 3.

%% Changes in ops and precedence should be reflected on lib/elixir/lib/macro.ex
%% Note though the operator => in practice has lower precedence than all others,
%% its entry in the table is only to support the %{user | foo => bar} syntax.
Left       5 do.
Right     10 stab_op_eol.     %% ->
Left      20 ','.
Nonassoc  30 capture_op_eol.  %% &
Left      40 in_match_op_eol. %% <-, \\ (allowed in matches along =)
Right     50 when_op_eol.     %% when
Right     60 type_op_eol.     %% ::
Right     70 pipe_op_eol.     %% |
Right     80 assoc_op_eol.    %% =>
Right     90 match_op_eol.    %% =
Left     130 or_op_eol.       %% ||, |||, or
Left     140 and_op_eol.      %% &&, &&&, and
Left     150 comp_op_eol.     %% ==, !=, =~, ===, !==
Left     160 rel_op_eol.      %% <, >, <=, >=
Left     170 arrow_op_eol.    %% |>, <<<, >>>, ~>>, <<~, ~>, <~, <~>, <|>
Left     180 in_op_eol.       %% in, not in
Left     190 three_op_eol.    %% ^^^
Right    200 two_op_eol.      %% ++, --, .., <>
Left     210 add_op_eol.      %% +, -
Left     220 mult_op_eol.     %% *, /
Nonassoc 300 unary_op_eol.    %% +, -, !, ^, not, ~~~
Left     310 dot_call_op.
Left     310 dot_op.          %% .
Nonassoc 320 at_op_eol.       %% @
Nonassoc 330 dot_identifier.

%%% MAIN FLOW OF EXPRESSIONS

grammar -> eoe : {'__block__', meta_from_token('$1'), []}.
grammar -> expr_list : to_block('$1').
grammar -> eoe expr_list : to_block('$2').
grammar -> expr_list eoe : to_block('$1').
grammar -> eoe expr_list eoe : to_block('$2').
grammar -> '$empty' : {'__block__', [], []}.

% Note expressions are on reverse order
expr_list -> expr : ['$1'].
expr_list -> expr_list eoe expr : ['$3' | '$1'].

expr -> matched_expr : '$1'.
expr -> no_parens_expr : '$1'.
expr -> unmatched_expr : '$1'.

%% In Elixir we have three main call syntaxes: with parentheses,
%% without parentheses and with do blocks. They are represented
%% in the AST as matched, no_parens and unmatched.
%%
%% Calls without parentheses are further divided according to how
%% problematic they are:
%%
%% (a) no_parens_one: a call with one unproblematic argument
%% (e.g. `f a` or `f g a` and similar) (includes unary operators)
%%
%% (b) no_parens_many: a call with several arguments (e.g. `f a, b`)
%%
%% (c) no_parens_one_ambig: a call with one argument which is
%% itself a no_parens_many or no_parens_one_ambig (e.g. `f g a, b`
%% or `f g h a, b` and similar)
%%
%% Note, in particular, that no_parens_one_ambig expressions are
%% ambiguous and are interpreted such that the outer function has
%% arity 1 (e.g. `f g a, b` is interpreted as `f(g(a, b))` rather
%% than `f(g(a), b)`). Hence the name, no_parens_one_ambig.
%%
%% The distinction is required because we can't, for example, have
%% a function call with a do block as argument inside another do
%% block call, unless there are parentheses:
%%
%%   if if true do true else false end do  #=> invalid
%%   if(if true do true else false end) do #=> valid
%%
%% Similarly, it is not possible to nest calls without parentheses
%% if their arity is more than 1:
%%
%%   foo a, bar b, c  #=> invalid
%%   foo(a, bar b, c) #=> invalid
%%   foo bar a, b     #=> valid
%%   foo a, bar(b, c) #=> valid
%%
%% So the different grammar rules need to take into account
%% if calls without parentheses are do blocks in particular
%% segments and act accordingly.
matched_expr -> matched_expr matched_op_expr : build_op(element(1, '$2'), '$1', element(2, '$2')).
matched_expr -> unary_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> at_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> capture_op_eol matched_expr : build_unary_op('$1', '$2').
matched_expr -> no_parens_one_expr : '$1'.
matched_expr -> no_parens_zero_expr : '$1'.
matched_expr -> access_expr : '$1'.
matched_expr -> access_expr kw_identifier : throw_invalid_kw_identifier('$2').

unmatched_expr -> matched_expr unmatched_op_expr : build_op(element(1, '$2'), '$1', element(2, '$2')).
unmatched_expr -> unmatched_expr matched_op_expr : build_op(element(1, '$2'), '$1', element(2, '$2')).
unmatched_expr -> unmatched_expr unmatched_op_expr : build_op(element(1, '$2'), '$1', element(2, '$2')).
unmatched_expr -> unmatched_expr no_parens_op_expr : build_op(element(1, '$2'), '$1', element(2, '$2')).
unmatched_expr -> unary_op_eol expr : build_unary_op('$1', '$2').
unmatched_expr -> at_op_eol expr : build_unary_op('$1', '$2').
unmatched_expr -> capture_op_eol expr : build_unary_op('$1', '$2').
unmatched_expr -> block_expr : '$1'.

no_parens_expr -> matched_expr no_parens_op_expr : build_op(element(1, '$2'), '$1', element(2, '$2')).
no_parens_expr -> unary_op_eol no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> at_op_eol no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> capture_op_eol no_parens_expr : build_unary_op('$1', '$2').
no_parens_expr -> no_parens_one_ambig_expr : '$1'.
no_parens_expr -> no_parens_many_expr : '$1'.

block_expr -> parens_call call_args_parens do_block : build_identifier('$1', '$2' ++ '$3').
block_expr -> parens_call call_args_parens call_args_parens do_block : build_nested_parens('$1', '$2', '$3' ++ '$4').
block_expr -> dot_do_identifier do_block : build_identifier('$1', '$2').
block_expr -> dot_op_identifier call_args_no_parens_all do_block : build_identifier('$1', '$2' ++ '$3').
block_expr -> dot_identifier call_args_no_parens_all do_block : build_identifier('$1', '$2' ++ '$3').

matched_op_expr -> match_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> add_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> mult_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> two_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> three_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> and_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> or_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> in_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> in_match_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> type_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> when_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> pipe_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> comp_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> rel_op_eol matched_expr : {'$1', '$2'}.
matched_op_expr -> arrow_op_eol matched_expr : {'$1', '$2'}.
%% Warn for no parens subset
matched_op_expr -> arrow_op_eol no_parens_one_expr : warn_pipe('$1', '$2'), {'$1', '$2'}.

unmatched_op_expr -> match_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> add_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> mult_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> two_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> three_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> and_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> or_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> in_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> in_match_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> type_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> when_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> pipe_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> comp_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> rel_op_eol unmatched_expr : {'$1', '$2'}.
unmatched_op_expr -> arrow_op_eol unmatched_expr : {'$1', '$2'}.

no_parens_op_expr -> match_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> add_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> mult_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> two_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> three_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> and_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> or_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> in_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> in_match_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> type_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> when_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> pipe_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> comp_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> rel_op_eol no_parens_expr : {'$1', '$2'}.
no_parens_op_expr -> arrow_op_eol no_parens_expr : {'$1', '$2'}.
%% Warn for no parens subset
no_parens_op_expr -> arrow_op_eol no_parens_one_ambig_expr : warn_pipe('$1', '$2'), {'$1', '$2'}.
no_parens_op_expr -> arrow_op_eol no_parens_many_expr : warn_pipe('$1', '$2'), {'$1', '$2'}.

%% Allow when (and only when) with keywords
no_parens_op_expr -> when_op_eol call_args_no_parens_kw : {'$1', '$2'}.

no_parens_one_ambig_expr -> dot_op_identifier call_args_no_parens_ambig : build_identifier('$1', '$2').
no_parens_one_ambig_expr -> dot_identifier call_args_no_parens_ambig : build_identifier('$1', '$2').

no_parens_many_expr -> dot_op_identifier call_args_no_parens_many_strict : build_identifier('$1', '$2').
no_parens_many_expr -> dot_identifier call_args_no_parens_many_strict : build_identifier('$1', '$2').

no_parens_one_expr -> dot_op_identifier call_args_no_parens_one : build_identifier('$1', '$2').
no_parens_one_expr -> dot_identifier call_args_no_parens_one : build_identifier('$1', '$2').
no_parens_zero_expr -> dot_do_identifier : build_identifier('$1', nil).
no_parens_zero_expr -> dot_identifier : build_identifier('$1', nil).

%% From this point on, we just have constructs that can be
%% used with the access syntax. Notice that (dot_)identifier
%% is not included in this list simply because the tokenizer
%% marks identifiers followed by brackets as bracket_identifier.
access_expr -> bracket_at_expr : '$1'.
access_expr -> bracket_expr : '$1'.
access_expr -> capture_op_eol int : build_unary_op('$1', number_value('$2')).
access_expr -> fn_eoe stab end_eoe : build_fn('$1', reverse('$2')).
access_expr -> open_paren stab close_paren : build_stab(reverse('$2')).
access_expr -> open_paren stab ';' close_paren : build_stab(reverse('$2')).
access_expr -> open_paren ';' stab ';' close_paren : build_stab(reverse('$3')).
access_expr -> open_paren ';' stab close_paren : build_stab(reverse('$3')).
access_expr -> open_paren ';' close_paren : build_stab([]).
access_expr -> empty_paren : warn_empty_paren('$1'), nil.
access_expr -> number : '$1'.
access_expr -> list : element(1, '$1').
access_expr -> map : '$1'.
access_expr -> tuple : '$1'.
access_expr -> 'true' : handle_literal(?id('$1'), '$1').
access_expr -> 'false' : handle_literal(?id('$1'), '$1').
access_expr -> 'nil' : handle_literal(?id('$1'), '$1').
access_expr -> bin_string : build_bin_string('$1', [{format, string}]).
access_expr -> list_string : build_list_string('$1', [{format, charlist}]).
access_expr -> bin_heredoc : build_bin_heredoc('$1').
access_expr -> list_heredoc : build_list_heredoc('$1').
access_expr -> bit_string : '$1'.
access_expr -> sigil : build_sigil('$1').
access_expr -> max_expr : '$1'.

%% Augment integer literals with representation format if wrap_literals_in_blocks option is true
number -> int : handle_literal(number_value('$1'), '$1', [{original, ?exprs('$1')}]).
number -> float : handle_literal(number_value('$1'), '$1', [{original, ?exprs('$1')}]).

%% Aliases and properly formed calls. Used by map_expr.
max_expr -> atom : handle_literal(?exprs('$1'), '$1', []).
max_expr -> atom_safe : build_quoted_atom('$1', true, []).
max_expr -> atom_unsafe : build_quoted_atom('$1', false, []).
max_expr -> parens_call call_args_parens : build_identifier('$1', '$2').
max_expr -> parens_call call_args_parens call_args_parens : build_nested_parens('$1', '$2', '$3').
max_expr -> dot_alias : '$1'.

bracket_arg -> open_bracket kw close_bracket : build_list('$1', '$2').
bracket_arg -> open_bracket container_expr close_bracket : build_list('$1', '$2').
bracket_arg -> open_bracket container_expr ',' close_bracket : build_list('$1', '$2').

bracket_expr -> dot_bracket_identifier bracket_arg : build_access(build_identifier('$1', nil), '$2').
bracket_expr -> access_expr bracket_arg : build_access('$1', '$2').

bracket_at_expr -> at_op_eol dot_bracket_identifier bracket_arg :
                     build_access(build_unary_op('$1', build_identifier('$2', nil)), '$3').
bracket_at_expr -> at_op_eol access_expr bracket_arg :
                     build_access(build_unary_op('$1', '$2'), '$3').

%% Blocks

do_block -> do_eoe 'end' :
              [[{handle_literal(do, '$1', [{format, keyword}]), handle_literal(nil, '$1')}]].
do_block -> do_eoe stab end_eoe :
              [[{handle_literal(do, '$1', [{format, keyword}]), build_stab(reverse('$2'))}]].
do_block -> do_eoe block_list 'end' :
              [[{handle_literal(do, '$1', [{format, keyword}]), handle_literal(nil, '$1')} | '$2']].
do_block -> do_eoe stab_eoe block_list 'end' :
              [[{handle_literal(do, '$1', [{format, keyword}]), build_stab(reverse('$2'))} | '$3']].

eoe -> eol : '$1'.
eoe -> ';' : '$1'.
eoe -> eol ';' : '$1'.

fn_eoe -> 'fn' : '$1'.
fn_eoe -> 'fn' eoe : '$1'.

do_eoe -> 'do' : '$1'.
do_eoe -> 'do' eoe : '$1'.

end_eoe -> 'end' : '$1'.
end_eoe -> eoe 'end' : '$2'.

block_eoe -> block_identifier : '$1'.
block_eoe -> block_identifier eoe : '$1'.

stab -> stab_expr : ['$1'].
stab -> stab eoe stab_expr : ['$3' | '$1'].

stab_eoe -> stab : '$1'.
stab_eoe -> stab eoe : '$1'.

%% Here, `element(1, Token)` is the stab operator,
%% while `element(2, Token)` is the expression.
stab_expr -> expr :
               '$1'.
stab_expr -> stab_op_eol_and_expr :
               build_op(element(1, '$1'), [], element(2, '$1')).
stab_expr -> empty_paren stab_op_eol_and_expr :
               build_op(element(1, '$2'), [], element(2, '$2')).
stab_expr -> empty_paren when_op expr stab_op_eol_and_expr :
               build_op(element(1, '$4'), [{'when', meta_from_token('$2'), ['$3']}], element(2, '$4')).
stab_expr -> call_args_no_parens_all stab_op_eol_and_expr :
               build_op(element(1, '$2'), unwrap_when(unwrap_splice('$1')), element(2, '$2')).
stab_expr -> stab_parens_many stab_op_eol_and_expr :
               build_op(element(1, '$2'), unwrap_splice('$1'), element(2, '$2')).
stab_expr -> stab_parens_many when_op expr stab_op_eol_and_expr :
               build_op(element(1, '$4'), [{'when', meta_from_token('$2'), unwrap_splice('$1') ++ ['$3']}], element(2, '$4')).

stab_op_eol_and_expr -> stab_op_eol expr : {'$1', '$2'}.
stab_op_eol_and_expr -> stab_op_eol : warn_empty_stab_clause('$1'), {'$1', nil}.

block_item -> block_eoe stab_eoe :
                {handle_literal(?exprs('$1'), '$1', [{format, keyword}]), build_stab(reverse('$2'))}.
block_item -> block_eoe :
                {handle_literal(?exprs('$1'), '$1', [{format, keyword}]), handle_literal(nil, '$1')}.

block_list -> block_item : ['$1'].
block_list -> block_item block_list : ['$1' | '$2'].

%% Helpers

open_paren -> '('      : '$1'.
open_paren -> '(' eol  : '$1'.
close_paren -> ')'     : '$1'.
close_paren -> eol ')' : '$2'.

empty_paren -> open_paren ')' : '$1'.

open_bracket  -> '['     : '$1'.
open_bracket  -> '[' eol : '$1'.
close_bracket -> ']'     : '$1'.
close_bracket -> eol ']' : '$2'.

open_bit  -> '<<'     : '$1'.
open_bit  -> '<<' eol : '$1'.
close_bit -> '>>'     : '$1'.
close_bit -> eol '>>' : '$2'.

open_curly  -> '{'     : '$1'.
open_curly  -> '{' eol : '$1'.
close_curly -> '}'     : '$1'.
close_curly -> eol '}' : '$2'.

% Operators

add_op_eol -> add_op : '$1'.
add_op_eol -> add_op eol : '$1'.
add_op_eol -> dual_op : '$1'.
add_op_eol -> dual_op eol : '$1'.

mult_op_eol -> mult_op : '$1'.
mult_op_eol -> mult_op eol : '$1'.

two_op_eol -> two_op : '$1'.
two_op_eol -> two_op eol : '$1'.

three_op_eol -> three_op : '$1'.
three_op_eol -> three_op eol : '$1'.

pipe_op_eol -> pipe_op : '$1'.
pipe_op_eol -> pipe_op eol : '$1'.

capture_op_eol -> capture_op : '$1'.
capture_op_eol -> capture_op eol : '$1'.

unary_op_eol -> unary_op : '$1'.
unary_op_eol -> unary_op eol : '$1'.
unary_op_eol -> dual_op : '$1'.
unary_op_eol -> dual_op eol : '$1'.

match_op_eol -> match_op : '$1'.
match_op_eol -> match_op eol : '$1'.

and_op_eol -> and_op : '$1'.
and_op_eol -> and_op eol : '$1'.

or_op_eol -> or_op : '$1'.
or_op_eol -> or_op eol : '$1'.

in_op_eol -> in_op : '$1'.
in_op_eol -> in_op eol : '$1'.

in_match_op_eol -> in_match_op : '$1'.
in_match_op_eol -> in_match_op eol : '$1'.

type_op_eol -> type_op : '$1'.
type_op_eol -> type_op eol : '$1'.

when_op_eol -> when_op : '$1'.
when_op_eol -> when_op eol : '$1'.

stab_op_eol -> stab_op : '$1'.
stab_op_eol -> stab_op eol : '$1'.

at_op_eol -> at_op : '$1'.
at_op_eol -> at_op eol : '$1'.

comp_op_eol -> comp_op : '$1'.
comp_op_eol -> comp_op eol : '$1'.

rel_op_eol -> rel_op : '$1'.
rel_op_eol -> rel_op eol : '$1'.

arrow_op_eol -> arrow_op : '$1'.
arrow_op_eol -> arrow_op eol : '$1'.

% Dot operator

dot_op -> '.' : '$1'.
dot_op -> '.' eol : '$1'.

dot_identifier -> identifier : '$1'.
dot_identifier -> matched_expr dot_op identifier : build_dot('$2', '$1', '$3').

dot_alias -> alias : build_alias('$1', [], '$1').
dot_alias -> matched_expr dot_op alias : build_dot_alias('$2', '$1', '$3').
dot_alias -> matched_expr dot_op dot_alias_container : build_dot_container('$2', '$1', '$3').

dot_alias_container -> open_curly '}' : [].
dot_alias_container -> open_curly container_args close_curly : '$2'.

dot_op_identifier -> op_identifier : '$1'.
dot_op_identifier -> matched_expr dot_op op_identifier : build_dot('$2', '$1', '$3').

dot_do_identifier -> do_identifier : '$1'.
dot_do_identifier -> matched_expr dot_op do_identifier : build_dot('$2', '$1', '$3').

dot_bracket_identifier -> bracket_identifier : '$1'.
dot_bracket_identifier -> matched_expr dot_op bracket_identifier : build_dot('$2', '$1', '$3').

dot_paren_identifier -> paren_identifier : '$1'.
dot_paren_identifier -> matched_expr dot_op paren_identifier : build_dot('$2', '$1', '$3').

parens_call -> dot_paren_identifier : '$1'.
parens_call -> matched_expr dot_call_op : {'.', meta_from_token('$2'), ['$1']}. % Fun/local calls

% Function calls with no parentheses

call_args_no_parens_expr -> matched_expr : '$1'.
call_args_no_parens_expr -> no_parens_expr : throw_no_parens_many_strict('$1').

call_args_no_parens_comma_expr -> matched_expr ',' call_args_no_parens_expr : ['$3', '$1'].
call_args_no_parens_comma_expr -> call_args_no_parens_comma_expr ',' call_args_no_parens_expr : ['$3' | '$1'].

call_args_no_parens_all -> call_args_no_parens_one : '$1'.
call_args_no_parens_all -> call_args_no_parens_ambig : '$1'.
call_args_no_parens_all -> call_args_no_parens_many : '$1'.

call_args_no_parens_one -> call_args_no_parens_kw : ['$1'].
call_args_no_parens_one -> matched_expr : ['$1'].

call_args_no_parens_ambig -> no_parens_expr : ['$1'].

call_args_no_parens_many -> matched_expr ',' call_args_no_parens_kw : ['$1', '$3'].
call_args_no_parens_many -> call_args_no_parens_comma_expr : reverse('$1').
call_args_no_parens_many -> call_args_no_parens_comma_expr ',' call_args_no_parens_kw : reverse(['$3' | '$1']).

call_args_no_parens_many_strict -> call_args_no_parens_many : '$1'.
call_args_no_parens_many_strict -> open_paren call_args_no_parens_kw close_paren : throw_no_parens_strict('$1').
call_args_no_parens_many_strict -> open_paren call_args_no_parens_many close_paren : throw_no_parens_strict('$1').

stab_parens_many -> open_paren call_args_no_parens_kw close_paren : ['$2'].
stab_parens_many -> open_paren call_args_no_parens_many close_paren : '$2'.

% Containers

container_expr -> matched_expr : '$1'.
container_expr -> unmatched_expr : '$1'.
container_expr -> no_parens_expr : throw_no_parens_container_strict('$1').

container_args_base -> container_expr : ['$1'].
container_args_base -> container_args_base ',' container_expr : ['$3' | '$1'].

container_args -> container_args_base : lists:reverse('$1').
container_args -> container_args_base ',' : lists:reverse('$1').
container_args -> container_args_base ',' kw : lists:reverse(['$3' | '$1']).

% Function calls with parentheses

call_args_parens_expr -> matched_expr : '$1'.
call_args_parens_expr -> unmatched_expr : '$1'.
call_args_parens_expr -> no_parens_expr : throw_no_parens_many_strict('$1').

call_args_parens_base -> call_args_parens_expr : ['$1'].
call_args_parens_base -> call_args_parens_base ',' call_args_parens_expr : ['$3' | '$1'].

call_args_parens -> empty_paren : [].
call_args_parens -> open_paren no_parens_expr close_paren : ['$2'].
call_args_parens -> open_paren kw close_paren : ['$2'].
call_args_parens -> open_paren call_args_parens_base close_paren : reverse('$2').
call_args_parens -> open_paren call_args_parens_base ',' kw close_paren : reverse(['$4' | '$2']).

% KV

kw_eol -> kw_identifier : handle_literal(?exprs('$1'), '$1', [{format, keyword}]).
kw_eol -> kw_identifier eol : handle_literal(?exprs('$1'), '$1', [{format, keyword}]).
kw_eol -> kw_identifier_safe : build_quoted_atom('$1', true, [{format, keyword}]).
kw_eol -> kw_identifier_safe eol : build_quoted_atom('$1', true, [{format, keyword}]).
kw_eol -> kw_identifier_unsafe : build_quoted_atom('$1', false, [{format, keyword}]).
kw_eol -> kw_identifier_unsafe eol : build_quoted_atom('$1', false, [{format, keyword}]).

kw_base -> kw_eol container_expr : [{'$1', '$2'}].
kw_base -> kw_base ',' kw_eol container_expr : [{'$3', '$4'} | '$1'].

kw -> kw_base : reverse('$1').
kw -> kw_base ',' : reverse('$1').

call_args_no_parens_kw_expr -> kw_eol matched_expr : {'$1', '$2'}.
call_args_no_parens_kw_expr -> kw_eol no_parens_expr : {'$1', '$2'}.

call_args_no_parens_kw -> call_args_no_parens_kw_expr : ['$1'].
call_args_no_parens_kw -> call_args_no_parens_kw_expr ',' call_args_no_parens_kw : ['$1' | '$3'].

% Lists

list_args -> kw : '$1'.
list_args -> container_args_base : reverse('$1').
list_args -> container_args_base ',' : reverse('$1').
list_args -> container_args_base ',' kw : reverse('$1', '$3').

list -> open_bracket ']' : build_list('$1', []).
list -> open_bracket list_args close_bracket : build_list('$1', '$2').

% Tuple

tuple -> open_curly '}' : build_tuple('$1', []).
tuple -> open_curly container_args close_curly :  build_tuple('$1', '$2').

% Bitstrings

bit_string -> open_bit '>>' : build_bit('$1', []).
bit_string -> open_bit container_args close_bit : build_bit('$1', '$2').

% Map and structs

%% Allow unquote/@something/aliases inside maps and structs.
map_expr -> max_expr : '$1'.
map_expr -> dot_identifier : build_identifier('$1', nil).
map_expr -> unary_op_eol map_expr : build_unary_op('$1', '$2').
map_expr -> at_op_eol map_expr : build_unary_op('$1', '$2').

assoc_op_eol -> assoc_op : '$1'.
assoc_op_eol -> assoc_op eol : '$1'.

assoc_expr -> matched_expr assoc_op_eol matched_expr : {'$1', '$3'}.
assoc_expr -> unmatched_expr assoc_op_eol unmatched_expr : {'$1', '$3'}.
assoc_expr -> matched_expr assoc_op_eol unmatched_expr : {'$1', '$3'}.
assoc_expr -> unmatched_expr assoc_op_eol matched_expr : {'$1', '$3'}.
assoc_expr -> map_expr : '$1'.

assoc_update -> matched_expr pipe_op_eol assoc_expr : {'$2', '$1', ['$3']}.
assoc_update -> unmatched_expr pipe_op_eol assoc_expr : {'$2', '$1', ['$3']}.

assoc_update_kw -> matched_expr pipe_op_eol kw : {'$2', '$1', '$3'}.
assoc_update_kw -> unmatched_expr pipe_op_eol kw : {'$2', '$1', '$3'}.

assoc_base -> assoc_expr : ['$1'].
assoc_base -> assoc_base ',' assoc_expr : ['$3' | '$1'].

assoc -> assoc_base : reverse('$1').
assoc -> assoc_base ',' : reverse('$1').

map_op -> '%{}' : '$1'.
map_op -> '%{}' eol : '$1'.

map_close -> kw close_curly : '$1'.
map_close -> assoc close_curly : '$1'.
map_close -> assoc_base ',' kw close_curly : reverse('$1', '$3').

map_args -> open_curly '}' : build_map('$1', []).
map_args -> open_curly map_close : build_map('$1', '$2').
map_args -> open_curly assoc_update close_curly : build_map_update('$1', '$2', []).
map_args -> open_curly assoc_update ',' close_curly : build_map_update('$1', '$2', []).
map_args -> open_curly assoc_update ',' map_close : build_map_update('$1', '$2', '$4').
map_args -> open_curly assoc_update_kw close_curly : build_map_update('$1', '$2', []).

struct_op -> '%' : '$1'.

map -> map_op map_args : '$2'.
map -> struct_op map_expr map_args : {'%', meta_from_token('$1'), ['$2', '$3']}.
map -> struct_op map_expr eol map_args : {'%', meta_from_token('$1'), ['$2', '$4']}.

Erlang code.

-define(file(), get(elixir_parser_file)).
-define(id(Token), element(1, Token)).
-define(location(Token), element(2, Token)).
-define(exprs(Token), element(3, Token)).
-define(meta(Node), element(2, Node)).
-define(rearrange_uop(Op), (Op == 'not' orelse Op == '!')).

%% The following directive is needed for (significantly) faster
%% compilation of the generated .erl file by the HiPE compiler
-compile([{hipe, [{regalloc, linear_scan}]}]).
-import(lists, [reverse/1, reverse/2]).

meta_from_token(Token) -> meta_from_location(?location(Token)).

meta_from_location({Line, {Column, EndColumn}, _})
  when is_integer(Line), is_integer(Column), is_integer(EndColumn) -> [{line, Line}].

%% Handle metadata in literals

handle_literal(Literal, Token) ->
  handle_literal(Literal, Token, []).

handle_literal(Literal, Token, ExtraMeta) ->
  case get(wrap_literals_in_blocks) of
    true -> {'__block__', ExtraMeta ++ meta_from_token(Token), [Literal]};
    false -> Literal
  end.

number_value({_, {_, _, Value}, _}) ->
  Value.

%% Operators

build_op({_Kind, Location, 'in'}, {UOp, _, [Left]}, Right) when ?rearrange_uop(UOp) ->
  %% TODO: Deprecate "not left in right" rearrangement on 1.7
  {UOp, meta_from_location(Location), [{'in', meta_from_location(Location), [Left, Right]}]};
build_op({_Kind, Location, 'not in'}, Left, Right) ->
  {'not', meta_from_location(Location), [{'in', meta_from_location(Location), [Left, Right]}]};
build_op({_Kind, Location, Op}, Left, Right) ->
  {Op, meta_from_location(Location), [Left, Right]}.

build_unary_op({_Kind, Location, Op}, Expr) ->
  {Op, meta_from_location(Location), [Expr]}.

build_list(Marker, Args) ->
  {handle_literal(Args, Marker), ?location(Marker)}.

build_tuple(Marker, [Left, Right]) ->
  handle_literal({Left, Right}, Marker);
build_tuple(Marker, Args) ->
  {'{}', meta_from_token(Marker), Args}.

build_bit(Marker, Args) ->
  {'<<>>', meta_from_token(Marker), Args}.

build_map(Marker, Args) ->
  {'%{}', meta_from_token(Marker), Args}.

build_map_update(Marker, {Pipe, Left, Right}, Extra) ->
  {'%{}', meta_from_token(Marker), [build_op(Pipe, Left, Right ++ Extra)]}.

%% Blocks

build_block([{Op, _, [_]}]=Exprs) when ?rearrange_uop(Op) ->
  {'__block__', [], Exprs};
build_block([{unquote_splicing, _, [_]}]=Exprs) ->
  {'__block__', [], Exprs};
build_block([Expr]) ->
  Expr;
build_block(Exprs) ->
  {'__block__', [], Exprs}.

%% Dots

build_alias(Dot, Left, {'alias', _, Right}) ->
  Meta =
    case get(wrap_literals_in_blocks) of
      true -> [{format, alias}] ++ meta_from_token(Dot);
      false -> meta_from_token(Dot)
    end,
  {'__aliases__', Meta, Left ++ [Right]}.

build_dot_alias(Dot, {'__aliases__', _, Left}, Right) ->
  build_alias(Dot, Left, Right);
build_dot_alias(_Dot, Atom, Right) when is_atom(Atom) ->
  throw_bad_atom(Right);
build_dot_alias(Dot, Expr, Right) ->
  build_alias(Dot, [Expr], Right).

build_dot_container(Dot, Left, Right) ->
  Meta = meta_from_token(Dot),
  {{'.', Meta, [Left, '{}']}, Meta, Right}.

build_dot(Dot, Left, Right) ->
  {'.', meta_from_token(Dot), [Left, extract_identifier(Right)]}.

extract_identifier({Kind, _, Identifier}) when
    Kind == identifier; Kind == bracket_identifier; Kind == paren_identifier;
    Kind == do_identifier; Kind == op_identifier ->
  Identifier.

%% Identifiers

build_nested_parens(Dot, Args1, Args2) ->
  Identifier = build_identifier(Dot, Args1),
  Meta = ?meta(Identifier),
  {Identifier, Meta, Args2}.

build_identifier({'.', Meta, _} = Dot, Args) ->
  FArgs = case Args of
    nil -> [];
    _ -> Args
  end,
  {Dot, Meta, FArgs};

build_identifier({op_identifier, Location, Identifier}, [Arg]) ->
  {Identifier, [{ambiguous_op, nil} | meta_from_location(Location)], [Arg]};

build_identifier({_, Location, Identifier}, Args) ->
  {Identifier, meta_from_location(Location), Args}.

%% Fn

build_fn(Op, [{'->', _, [_, _]} | _] = Stab) ->
  {fn, meta_from_token(Op), build_stab(Stab)};
build_fn(Op, _Stab) ->
  throw(meta_from_token(Op), "expected clauses to be defined with -> inside: ", "'fn'").

%% Access

build_access(Expr, {List, Location}) ->
  Meta = meta_from_location(Location),
  {{'.', Meta, ['Elixir.Access', get]}, Meta, [Expr, List]}.

%% Interpolation aware

build_sigil({sigil, Location, Sigil, Parts, Modifiers, Terminator}) ->
  Meta = meta_from_location(Location),
  MetaWithTerminator = [{terminator, Terminator} | Meta],
  {list_to_atom("sigil_" ++ [Sigil]),
   MetaWithTerminator,
   [{'<<>>', Meta, string_parts(Parts)}, Modifiers]}.

build_bin_heredoc({bin_heredoc, Location, Args}) ->
  build_bin_string({bin_string, Location, Args}, [{format, bin_heredoc}]).

build_list_heredoc({list_heredoc, Location, Args}) ->
  build_list_string({list_string, Location, Args}, [{format, list_heredoc}]).

build_bin_string({bin_string, _Location, [H]} = Token, ExtraMeta) when is_binary(H) ->
  handle_literal(H, Token, ExtraMeta);
build_bin_string({bin_string, Location, Args}, ExtraMeta) ->
  Meta =
    case get(wrap_literals_in_blocks) of
      true -> ExtraMeta ++ meta_from_location(Location);
      false -> meta_from_location(Location)
    end,
  {'<<>>', Meta, string_parts(Args)}.

build_list_string({list_string, _Location, [H]} = Token, ExtraMeta) when is_binary(H) ->
  handle_literal(elixir_utils:characters_to_list(H), Token, ExtraMeta);
build_list_string({list_string, Location, Args}, ExtraMeta) ->
  Meta = meta_from_location(Location),
  MetaWithExtra =
    case get(wrap_literals_in_blocks) of
      true -> ExtraMeta ++ Meta;
      false -> Meta
    end,
  {{'.', Meta, ['Elixir.String', to_charlist]}, Meta, [{'<<>>', MetaWithExtra, string_parts(Args)}]}.

build_quoted_atom({_, _Location, [H]} = Token, Safe, ExtraMeta) when is_binary(H) ->
  Op = binary_to_atom_op(Safe),
  handle_literal(erlang:Op(H, utf8), Token, ExtraMeta);
build_quoted_atom({_, Location, Args}, Safe, ExtraMeta) ->
  Meta = meta_from_location(Location),
  MetaWithExtra =
    case get(wrap_literals_in_blocks) of
      true -> ExtraMeta ++ Meta;
      false -> Meta
    end,
  {{'.', Meta, [erlang, binary_to_atom_op(Safe)]}, Meta, [{'<<>>', MetaWithExtra, string_parts(Args)}, utf8]}.

binary_to_atom_op(true)  -> binary_to_existing_atom;
binary_to_atom_op(false) -> binary_to_atom.

string_parts(Parts) ->
  [string_part(Part) || Part <- Parts].
string_part(Binary) when is_binary(Binary) ->
  Binary;
string_part({Location, Tokens}) ->
  Form = string_tokens_parse(Tokens),
  Meta = meta_from_location(Location),
  {'::', Meta, [{{'.', Meta, ['Elixir.Kernel', to_string]}, Meta, [Form]}, {binary, Meta, nil}]}.

string_tokens_parse(Tokens) ->
  case parse(Tokens) of
    {ok, Forms} -> Forms;
    {error, _} = Error -> throw(Error)
  end.

%% Keywords

build_stab([{'->', Meta, [Left, Right]} | T]) ->
  build_stab(Meta, T, Left, [Right], []);

build_stab(Else) ->
  build_block(Else).

build_stab(Old, [{'->', New, [Left, Right]} | T], Marker, Temp, Acc) ->
  H = {'->', Old, [Marker, build_block(reverse(Temp))]},
  build_stab(New, T, Left, [Right], [H | Acc]);

build_stab(Meta, [H | T], Marker, Temp, Acc) ->
  build_stab(Meta, T, Marker, [H | Temp], Acc);

build_stab(Meta, [], Marker, Temp, Acc) ->
  H = {'->', Meta, [Marker, build_block(reverse(Temp))]},
  reverse([H | Acc]).

%% Every time the parser sees a (unquote_splicing())
%% it assumes that a block is being spliced, wrapping
%% the splicing in a __block__. But in the stab clause,
%% we can have (unquote_splicing(1, 2, 3)) -> :ok, in such
%% case, we don't actually want the block, since it is
%% an arg style call. unwrap_splice unwraps the splice
%% from such blocks.
unwrap_splice([{'__block__', [], [{unquote_splicing, _, _}] = Splice}]) ->
  Splice;

unwrap_splice(Other) -> Other.

unwrap_when(Args) ->
  case elixir_utils:split_last(Args) of
    {Start, {'when', Meta, [_, _] = End}} ->
      [{'when', Meta, Start ++ End}];
    {_, _} ->
      Args
  end.

to_block([One]) -> One;
to_block(Other) -> {'__block__', [], reverse(Other)}.

%% Warnings and errors

throw(Meta, Error, Token) ->
  Line =
    case lists:keyfind(line, 1, Meta) of
      {line, L} -> L;
      false -> 0
    end,
  throw({error, {Line, ?MODULE, [Error, Token]}}).

throw_bad_atom(Token) ->
  throw(meta_from_token(Token), "atom cannot be followed by an alias. If the '.' was meant to be "
    "part of the atom's name, the atom name must be quoted. Syntax error before: ", "'.'").

throw_no_parens_strict(Token) ->
  throw(meta_from_token(Token), "unexpected parentheses. If you are making a "
    "function call, do not insert spaces between the function name and the "
    "opening parentheses. Syntax error before: ", "'('").

throw_no_parens_many_strict(Node) ->
  throw(?meta(Node),
    "unexpected comma. Parentheses are required to solve ambiguity in nested calls.\n\n"
    "This error happens when you have nested function calls without parentheses. "
    "For example:\n\n"
    "    one a, two b, c, d\n\n"
    "In the example above, we don't know if the parameters \"c\" and \"d\" apply "
    "to the function \"one\" or \"two\". You can solve this by explicitly adding "
    "parentheses:\n\n"
    "    one a, two(b, c, d)\n\n"
    "Or by adding commas (in case a nested call is not intended):\n\n"
    "    one, a, two, b, c, d\n\n"
    "Elixir cannot compile otherwise. Syntax error before: ", "','").

throw_no_parens_container_strict(Node) ->
  throw(?meta(Node),
    "unexpected comma. Parentheses are required to solve ambiguity inside containers.\n\n"
    "This error may happen when you forget a comma in a list or other container:\n\n"
    "    [a, b c, d]\n\n"
    "Or when you have ambiguous calls:\n\n"
    "    [one, two three, four, five]\n\n"
    "In the example above, we don't know if the parameters \"four\" and \"five\" "
    "belongs to the list or the function \"two\". You can solve this by explicitly "
    "adding parentheses:\n\n"
    "    [one, two(three, four), five]\n\n"
    "Elixir cannot compile otherwise. Syntax error before: ", "','").

throw_invalid_kw_identifier({_, _, do} = Token) ->
  throw(meta_from_token(Token), elixir_tokenizer:invalid_do_error("unexpected keyword \"do:\""), "'do:'");
throw_invalid_kw_identifier({_, _, KW} = Token) ->
  throw(meta_from_token(Token), "syntax error before: ", "'" ++ atom_to_list(KW) ++ "':").

%% TODO: Make this an error on Elixir v2.0.
warn_empty_paren({_, {Line, _, _}}) ->
  elixir_errors:warn(Line, ?file(),
    "invalid expression (). "
    "If you want to invoke or define a function, make sure there are "
    "no spaces between the function name and its arguments. If you wanted "
    "to pass an empty block, pass a value instead, such as a nil or an atom").

%% TODO: Make this an error on Elixir v2.0.
warn_empty_stab_clause({stab_op, {Line, _Begin, _End}, '->'}) ->
  elixir_errors:warn(Line, ?file(),
    "an expression is always required on the right side of ->. "
    "Please provide a value after ->").

warn_pipe({arrow_op, {Line, _Begin, _End}, Op}, {_, [_ | _], [_ | _]}) ->
  elixir_errors:warn(Line, ?file(),
    io_lib:format(
      "parentheses are required when piping into a function call. For example:\n\n"
      "    foo 1 ~ts bar 2 ~ts baz 3\n\n"
      "is ambiguous and should be written as\n\n"
      "    foo(1) ~ts bar(2) ~ts baz(3)\n\n"
      "Ambiguous pipe found at:",
      [Op, Op, Op, Op]
    )
  );
warn_pipe(_Token, _) ->
  ok.
