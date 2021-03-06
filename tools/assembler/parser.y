// 
// Copyright 2011-2012 Jeff Bush
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// 


%{

#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include "code_output.h"
#include "symbol_table.h"
#include "debug_info.h"

void yyerror(char *string);
int yylex(void);

static char *currentSourceFile;
static int errorCount = 0;

enum MemoryAccessWidth decodeMemorySpecifier(const char *spec)
{
	if (strcmp(spec, "mem_b") == 0)
		return MA_BYTE;
	else if (strcmp(spec, "mem_s") == 0)
		return MA_SHORT;
	else if (strcmp(spec, "mem_l") == 0)
		return MA_LONG;
	else if (strcmp(spec, "mem_sync") == 0)
		return MA_SYNC;
	else
		return -1;
}

void printAssembleError(const char *filename, int lineno, const char *fmt, ...)
{
	va_list va;

	fprintf(stderr, "%s:%d: ", filename, lineno);
	
	va_start(va, fmt);
	vfprintf(stderr, fmt, va);
	va_end(va);
	errorCount++;
}

%}

%locations
%error-verbose

%token TOK_INTEGER_LITERAL TOK_FLOAT_LITERAL TOK_REGISTER TOK_ALIGN
%token TOK_IDENTIFIER TOK_KEYWORD TOK_CONSTANT TOK_MEMORY_SPECIFIER
%token TOK_WORD TOK_SHORT TOK_BYTE TOK_STRING TOK_LITERAL_STRING
%token TOK_EQUAL_EQUAL TOK_GREATER_EQUAL TOK_LESS_EQUAL TOK_NOT_EQUAL
%token TOK_SHL TOK_SHR TOK_FLOAT TOK_NOP TOK_CONTROL_REGISTER
%token TOK_IF TOK_GOTO TOK_ALL TOK_CALL TOK_RESERVE TOK_REG_ALIAS
%token TOK_ENTER_SCOPE TOK_EXIT_SCOPE TOK_LABELDEF TOK_SAVEREGS TOK_RESTOREREGS
%token TOK_DPRELOAD TOK_DINVALIDATE TOK_DFLUSH TOK_IINVALIDATE TOK_STBAR
%token TOK_EMIT_LITERAL_POOL

%left '|'
%left '^'
%left '&'
%left '+' '-'
%left '*' '/'

%type <reg> TOK_REGISTER TOK_CONTROL_REGISTER
%type <mask> maskSpec
%type <intval> TOK_INTEGER_LITERAL constExpr cacheOp
%type <sym> TOK_IDENTIFIER TOK_CONSTANT TOK_KEYWORD TOK_LABELDEF
%type <str> TOK_MEMORY_SPECIFIER TOK_LITERAL_STRING
%type <opType> operator
%type <floatval> TOK_FLOAT_LITERAL
%type <regmask> reglist

%union
{
	struct RegisterInfo reg;
	struct MaskInfo mask;
	int intval;
	float floatval;
	struct Symbol *sym;
	char str[256];
	enum OpType opType;
	unsigned long long int regmask;
}

%start sequence

%%

sequence		:	expr sequence
				|	expr
				;

expr			:	typeAExpr
				|	typeBExpr
				|	typeCExpr
				|	typeDExpr
				|	typeEExpr
				| 	constDecl
				|	dataExpr
				|	TOK_LABELDEF { emitLabel(@$.first_line, $1); }
				|	TOK_NOP { emitNop(@$.first_line); }
				| 	TOK_ALIGN constExpr { align($2); }
				|	TOK_RESERVE constExpr { reserve($2); }
				| 	TOK_SAVEREGS reglist { saveRegs($2, @$.first_line); }
				| 	TOK_RESTOREREGS reglist { restoreRegs($2, @$.first_line); }
				|	TOK_ENTER_SCOPE { enterScope(); }
				| 	TOK_EXIT_SCOPE { exitScope(); }
				|	TOK_EMIT_LITERAL_POOL { emitLiteralPoolValues(@$.first_line); }
				|	TOK_REG_ALIAS TOK_IDENTIFIER TOK_REGISTER
					{
						if ($2->type != SYM_LABEL || $2->defined)
						{
							printAssembleError(currentSourceFile, @$.first_line, "Redefined symbol %s\n",
								$2->name);
						}
						else
						{
							$2->type = SYM_REGISTER_ALIAS;
							$2->regInfo = $3;
						}
					}
				|	TOK_REG_ALIAS TOK_REGISTER TOK_REGISTER
					{
						// Because of the way this was implemented, this can
						// produce confusing errors.  Add a rule explicitly to
						// warn the user.
						printAssembleError(currentSourceFile, @$.first_line, 
							"Invalid name for register alias.  Either you are using a register for the first parameter or this was already defined.\n");
					}
				;

typeAExpr		:	TOK_REGISTER maskSpec '=' TOK_REGISTER operator TOK_REGISTER
					{
						emitAInstruction(&$1, &$2, &$4, $5, &$6, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_KEYWORD '(' TOK_REGISTER ')'
					{
						emitAInstruction(&$1, &$2, NULL, $4->value, &$6, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_KEYWORD '(' TOK_REGISTER ',' TOK_REGISTER ')'
					{
						emitAInstruction(&$1, &$2, &$6, $4->value, &$8, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' '~' TOK_REGISTER
					{
						emitAInstruction(&$1, &$2, NULL, OP_NOT, &$5, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' '-' TOK_REGISTER
					{
						emitAInstruction(&$1, &$2, NULL, OP_UMINUS, &$5, @$.first_line);
					}
				;
				

typeBExpr		:	TOK_REGISTER maskSpec '=' TOK_REGISTER operator constExpr
					{
						emitBInstruction(&$1, &$2, &$4, $5, $6, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_KEYWORD '(' TOK_REGISTER ',' constExpr ')'
					{
						emitBInstruction(&$1, &$2, &$6, $4->value, $8, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' '&' TOK_IDENTIFIER
					{
						if ($1.isVector || ($1.type != TYPE_SIGNED_INT
							&& $1.type != TYPE_UNSIGNED_INT))
						{
							printAssembleError(currentSourceFile, @$.first_line, 
								"invalid dest register type for address of (must be scalar integer)\n");
						}
						else
							emitLiteralPoolLabelRef(&$1, $5, @$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_FLOAT_LITERAL
					{
						if ($1.isVector || $1.type != TYPE_FLOAT)
						{
							printAssembleError(currentSourceFile, @$.first_line, 
								"invalid dest register type for literal (must be scalar float)\n");
						}
						else
						{
							unsigned int asInt = *((int*) &$4);
							emitLiteralPoolConstRef(&$1, asInt, @$.first_line);
						}
					}
				|	TOK_REGISTER maskSpec '=' constExpr
					{
						if ($4 > 0xfff || $4 < -0xfff)
						{
							// Won't fit directly, emit a constant pool reference
							if ($1.isVector || ($1.type != TYPE_SIGNED_INT
								&& $1.type != TYPE_UNSIGNED_INT))
							{
								printAssembleError(currentSourceFile, @$.first_line, 
									"invalid dest register type for literal (must be scalar integer)\n");
							}
							else
								emitLiteralPoolConstRef(&$1, $4, @$.first_line);
						}
						else
							emitBInstruction(&$1, &$2, NULL, OP_COPY, $4, @$.first_line);
					}
				| 	TOK_REGISTER maskSpec '=' TOK_REGISTER
					{
						emitBInstruction(&$1, &$2, &$4, OP_OR, 0, @$.first_line);
					}
				;
				
operator		:	'+' 				{ $$ = OP_PLUS; }
				|	'-' 				{ $$ = OP_MINUS; }
				|	'/' 				{ $$ = OP_DIVIDE; }
				|	'*' 				{ $$ = OP_MULTIPLY; }
				|	'~' 				{ $$ = OP_NOT; }
				| 	'|' 				{ $$ = OP_OR; }
				|	'^' 				{ $$ = OP_XOR; }
				|	'&' 				{ $$ = OP_AND; }
				|	'>' 				{ $$ = OP_GREATER; }
				|	'<'					{ $$ = OP_LESS; }
				|	TOK_EQUAL_EQUAL 	{ $$ = OP_EQUAL; }
				|	TOK_GREATER_EQUAL 	{ $$ = OP_GREATER_EQUAL; }
				| 	TOK_LESS_EQUAL 		{ $$ = OP_LESS_EQUAL; }
				|	TOK_NOT_EQUAL 		{ $$ = OP_NOT_EQUAL; }
				|	TOK_SHL 			{ $$ = OP_SHL; }
				|	TOK_SHR 			{ $$ = OP_SHR; }
				;
				
typeCExpr		:	TOK_REGISTER maskSpec '=' TOK_MEMORY_SPECIFIER '[' TOK_REGISTER ']'
					{
						emitCInstruction(&$6, 0, &$1, &$2, 1, 0, decodeMemorySpecifier($4),
							@$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_MEMORY_SPECIFIER '[' TOK_REGISTER '+' constExpr ']'
					{
						emitCInstruction(&$6, $8, &$1, &$2, 1, 0, decodeMemorySpecifier($4), 
							@$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_MEMORY_SPECIFIER '[' TOK_REGISTER '-' constExpr ']'
					{
						emitCInstruction(&$6, -$8, &$1, &$2, 1, 0, decodeMemorySpecifier($4), 
							@$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_MEMORY_SPECIFIER '[' TOK_REGISTER ',' constExpr ']'
					{
						emitCInstruction(&$6, $8, &$1, &$2, 1, 1, decodeMemorySpecifier($4), 
							@$.first_line);
					}
				|	TOK_MEMORY_SPECIFIER '[' TOK_REGISTER ']' maskSpec '=' TOK_REGISTER
					{
						emitCInstruction(&$3, 0, &$7, &$5, 0, 0, decodeMemorySpecifier($1), 
							@$.first_line);
					}
				|	TOK_MEMORY_SPECIFIER '[' TOK_REGISTER '+' constExpr ']'  maskSpec '=' TOK_REGISTER
					{
						emitCInstruction(&$3, $5, &$9, &$7, 0, 0, decodeMemorySpecifier($1),
							@$.first_line);
					}
				|	TOK_MEMORY_SPECIFIER '[' TOK_REGISTER '-' constExpr ']'  maskSpec '=' TOK_REGISTER
					{
						emitCInstruction(&$3, -$5, &$9, &$7, 0, 0, decodeMemorySpecifier($1),
							@$.first_line);
					}
				|	TOK_MEMORY_SPECIFIER '[' TOK_REGISTER ',' constExpr ']'  maskSpec '=' TOK_REGISTER
					{
						emitCInstruction(&$3, $5, &$9, &$7, 0, 1, decodeMemorySpecifier($1), 
							@$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_MEMORY_SPECIFIER '[' TOK_IDENTIFIER ']'
					{
						// PC relative load
						emitPCRelativeCInstruction($6, &$1, &$2, 1, decodeMemorySpecifier($4),
							@$.first_line);
					}
				|	TOK_MEMORY_SPECIFIER '[' TOK_IDENTIFIER ']' maskSpec '=' TOK_REGISTER
					{
						// PC relative store
						emitPCRelativeCInstruction($3, &$7, &$5, 0, decodeMemorySpecifier($1),
							@$.first_line);
					}
				|	TOK_CONTROL_REGISTER '=' TOK_REGISTER
					{
						emitCInstruction(&$1, 0, &$3, NULL, 0, 0, MA_CONTROL,
							@$.first_line);
					}
				|	TOK_REGISTER maskSpec '=' TOK_CONTROL_REGISTER
					{
						// XXX note that maskSpec is technically illegal here,
						// but I added it to remove a shift/reduce conflict.
						emitCInstruction(&$4, 0, &$1, &$2, 1, 0, MA_CONTROL,
							@$.first_line);
					}
				;
				
typeDExpr		:	cacheOp '(' TOK_REGISTER ')'
					{
						emitDInstruction($1, &$3, 0, @$.first_line);
					}
				|	cacheOp '(' TOK_REGISTER '+' constExpr ')'
					{
						emitDInstruction($1, &$3, $5, @$.first_line);
					}
				|	TOK_STBAR
					{
						emitDInstruction(CC_STBAR, NULL, 0, @$.first_line);
					}
				;
				
cacheOp			:	TOK_DPRELOAD 	{ $$ = CC_DPRELOAD; }
				|	TOK_DINVALIDATE	{ $$ = CC_DINVALIDATE; }
				|	TOK_DFLUSH 		{ $$ = CC_DFLUSH; }
				|	TOK_IINVALIDATE	{ $$ = CC_IINVALIDATE; }
				;
								
				
typeEExpr		:	TOK_GOTO TOK_IDENTIFIER
					{
						emitEInstruction($2, NULL, BRANCH_ALWAYS, @$.first_line);
					}
				|	TOK_CALL TOK_IDENTIFIER
					{
						emitEInstruction($2, NULL, BRANCH_CALL_OFFSET, @$.first_line);
					}
				|	TOK_CALL TOK_REGISTER
					{
						emitEInstruction(NULL, &$2, BRANCH_CALL_REGISTER, @$.first_line);
					}
				|	TOK_IF TOK_REGISTER TOK_GOTO TOK_IDENTIFIER
					{
						emitEInstruction($4, &$2, BRANCH_NOT_ZERO, @$.first_line);
					}
				|	TOK_IF '!' TOK_REGISTER TOK_GOTO TOK_IDENTIFIER
					{
						emitEInstruction($5, &$3, BRANCH_ZERO, @$.first_line);
					}
				|	TOK_IF TOK_ALL '(' TOK_REGISTER ')' TOK_GOTO TOK_IDENTIFIER
					{
						emitEInstruction($7, &$4, BRANCH_ALL, @$.first_line);
					}
				|	TOK_IF '!' TOK_ALL '(' TOK_REGISTER ')' TOK_GOTO TOK_IDENTIFIER
					{
						emitEInstruction($8, &$5, BRANCH_NOT_ALL, @$.first_line);
					}
				;

constDecl		:	TOK_IDENTIFIER '=' constExpr
					{
						if ($1->defined)
						{
							printAssembleError(currentSourceFile, @$.first_line, 
								"redefined symbol %s\n", $1->name);
						}
						else
						{
							$1->defined = 1;
							$1->type = SYM_CONSTANT;
							$1->value = $3;
						}
					}
				;

maskSpec		:	'{' TOK_REGISTER '}'
					{
						$$.maskReg = $2.index;
						if ($2.isVector || $2.type == TYPE_FLOAT)
						{
							printAssembleError(currentSourceFile, @$.first_line, 
								"invalid mask register type (must be scalar, integer)\n");
						}
						else
						{
							$$.hasMask = 1;
							$$.invertMask = 0;
						}
					}
				|	'{' '~' TOK_REGISTER '}'
					{
						$$.maskReg = $3.index;
						if ($3.isVector || $3.type == TYPE_FLOAT)
						{
							printAssembleError(currentSourceFile, @$.first_line, 
								"invalid mask register type (must be scalar, integer)\n");
						}
						else
						{
							$$.hasMask = 1;
							$$.invertMask = 1;
						}
					}
				|	/* Nothing */
					{
						$$.hasMask = 0;
						$$.invertMask = 0;
					}
				;
				
constExpr		:	'(' constExpr ')' { $$ = $2; }
				|	constExpr '+' constExpr { $$ = $1 + $3; }
				|	constExpr '-' constExpr { $$ = $1 - $3; }
				|	constExpr '*' constExpr { $$ = $1 * $3; }
				|	constExpr '/' constExpr { $$ = $1 / $3; }
				|	constExpr '&' constExpr { $$ = $1 & $3; }
				|	constExpr '|' constExpr { $$ = $1 | $3; }
				|	constExpr '^' constExpr { $$ = $1 ^ $3; }
				|	constExpr TOK_SHL constExpr { $$ = $1 << $3; }
				|	constExpr TOK_SHR constExpr { $$ = $1 >> $3; }
				|	TOK_INTEGER_LITERAL { $$ = $1; }
				|	TOK_CONSTANT { $$ = $1->value; }
				;
				
dataExpr		:	TOK_WORD wordList
				|	TOK_SHORT shortList
				|	TOK_BYTE byteList
				|	TOK_FLOAT floatList
				|	TOK_STRING TOK_LITERAL_STRING
					{
						const char *c;
						for (c = $2; *c; c++)
							emitByte(*c);
					}
				;

reglist			:	reglist ',' TOK_REGISTER
					{
						if ($3.isVector)
							$$ = $1 | (1LL << ($3.index + 32));
						else
							$$ = $1 | (1LL << $3.index);
					}
				|	TOK_REGISTER
					{
						if ($1.isVector)
							$$ = (1LL << ($1.index + 32));
						else
							$$ = (1LL << $1.index);
					}
				;				
				
floatList		:	floatList ',' TOK_FLOAT_LITERAL	{ emitLong(*((int*) &$3)); }
				|	floatList ',' TOK_INTEGER_LITERAL	{ float f = $3; emitLong(*((int*) &f)); }
				|	TOK_FLOAT_LITERAL 				{ emitLong(*((int*) &$1)); }
				|	TOK_INTEGER_LITERAL				{ float f = $1; emitLong(*((int*) &f)); }
				;
				
wordList		:	wordList ',' constExpr			{ emitLong($3); }
				|	constExpr 						{ emitLong($1); }
				| 	wordList ',' TOK_IDENTIFIER		{ emitLabelAddress($3, @$.first_line); }
				|	TOK_IDENTIFIER 					{ emitLabelAddress($1, @$.first_line);}
				;

shortList		:	shortList ',' constExpr	{ emitShort($3); }
				|	constExpr				{ emitShort($1); }
				;

byteList		:	byteList ',' constExpr	{ emitByte($3); }
				|	constExpr				{ emitByte($1); }
				;
				
%%

#include "lex.yy.c"

void yyerror(char *string)
{
	printAssembleError(currentSourceFile, yylloc.first_line, "%s\n", string);
}

int yywrap(void)
{
	return 1;	// No more files
}

// Returns 0 if successful, non-zero if failed
int parseSourceFile(const char *filename)
{
	yylineno = 1;
	debugInfoSetSourceFile(filename);
	codeOutputSetSourceFile(filename);
	free(currentSourceFile);
	currentSourceFile = strdup(filename);

	yyin = fopen(filename, "r");
	if (yyin == NULL)
	{
		fprintf(stderr, "Error opening source file %s\n", filename);
		return -1;
	}

	if (yyparse() != 0)
		return -1;

	if (errorCount != 0)
	{
		printf("%d errors\n", errorCount);
		return -1;
	}
	
	return 0;	
}
