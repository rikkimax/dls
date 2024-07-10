/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dcd.server.autocomplete.doc;

import std.stdio;
import std.algorithm;
import std.array;
import std.experimental.allocator;
import std.experimental.logger;
import std.typecons;

import dcd.server.autocomplete.util;

import dparse.ast;
import dparse.parser;
import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.modulecache;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.conversion;
import dsymbol.string_interning;

import dcd.common.messages;

import containers.hashset;

/**
 * Gets documentation for the symbol at the cursor
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse getDoc(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
//	trace("Getting doc comments");
	AutocompleteResponse response;
	RollbackAllocator rba;
	auto cache = StringCache(request.sourceCode.length.optimalBucketCount);
	SymbolStuff stuff = getSymbolsForCompletion(request, CompletionType.ddoc, &rba, cache, moduleCache);
	if (stuff.symbols.length == 0)
		warning("Could not find symbol");
	else
	{
		// first symbol allows ditto if it's the first documentation,
		// because then it takes documentation from a symbol with different name
		// which isn't inside the stuff.symbols range.
		bool firstSymbol = true;
		foreach(ref symbol; stuff.symbols.filter!(a => !a.doc.empty))
		{
			if (!firstSymbol && symbol.doc.ditto)
				continue;
			firstSymbol = false;

			AutocompleteResponse.Completion c = makeSymbolCompletionInfo(symbol, symbol.kind);
			c.documentation = symbol.doc;

			response.completions ~= c;
		}
	}
	return response;
}


public AutocompleteResponse getDocFull(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
//	trace("Getting doc comments");
	AutocompleteResponse response;
	RollbackAllocator rba;
	auto cache = StringCache(request.sourceCode.length.optimalBucketCount);
	SymbolStuff stuff = getSymbolsForCompletion(request, CompletionType.ddoc, &rba, cache, moduleCache);
	if (stuff.symbols.length == 0)
		warning("Could not find symbol");
	else
	{
		// first symbol allows ditto if it's the first documentation,
		// because then it takes documentation from a symbol with different name
		// which isn't inside the stuff.symbols range.
		bool firstSymbol = true;
		foreach(ref symbol; stuff.symbols)
		{
			if (!firstSymbol && (!symbol.doc.empty && symbol.doc.ditto))
				continue;
			firstSymbol = false;

			AutocompleteResponse.Completion c = makeSymbolCompletionInfo(symbol, symbol.kind);
			c.documentation = symbol.doc;

			response.completions ~= c;
		}
	}
	return response;
}



public AutocompleteResponse getFunctionCalltips(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
	// trace("Getting function calltips");
	AutocompleteResponse response;

	LexerConfig config;
	config.fileName = "";
	auto cache = StringCache(request.sourceCode.length.optimalBucketCount);
	auto tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode, config, &cache);
	RollbackAllocator rba;
	auto pair = generateAutocompleteTrees(tokenArray, &rba, -1, moduleCache);
	scope(exit) pair.destroy();

    void check(DSymbol* it, ref HashSet!size_t visited)
    {
        if (visited.contains(cast(size_t) it))
            return;
        if (it.symbolFile != "stdin") return;
    	visited.insert(cast(size_t) it);

        writeln("sym: ", it.name," ", it.location, " kind: ", it.kind," qualifier: ", it.qualifier);
        if (auto type = it.type)
        {
            writeln("   ", type.name, " kind: ", type.kind, " qualifier", type.qualifier);
        	if (auto ttype = type.type)
                writeln("      ", ttype.name, " kind: ", ttype.kind, " qualifier", ttype.qualifier);
        }


        foreach(part; it.opSlice())
            check(part, visited);
    }

    HashSet!size_t visited;
	foreach (symbol; pair.scope_.symbols)
	{
        check(symbol, visited);
        foreach(part; symbol.opSlice())
            check(part, visited);
    }



    //foreach(s; moduleCache.getAllSymbols())
    //{
    //    check(s.symbol, visited);
    //}

	return response;
}


struct CalltipsSupport
{
	///
	struct Argument
	{
		/// Ranges of type, name and value not including commas or parentheses, but being right next to them. For calls this is the only important and accurate value.
		int[2] contentRange;
		/// Range of just the type, or for templates also `alias`
		int[2] typeRange;
		/// Range of just the name
		int[2] nameRange;
		/// Range of just the default value
		int[2] valueRange;
		/// True if the type declaration is variadic (using ...), or without typeRange a completely variadic argument
		bool variadic;

		/// Creates Argument(range, range, range, 0)
		static Argument templateType(int[2] range)
		{
			return Argument(range, range, range);
		}

		/// Creates Argument(range, 0, range, range)
		static Argument templateValue(int[2] range)
		{
			return Argument(range, typeof(range).init, range, range);
		}

		/// Creates Argument(range, 0, 0, 0, true)
		static Argument anyVariadic(int[2] range)
		{
			return Argument(range, typeof(range).init, typeof(range).init, typeof(range).init, true);
		}
	}

	bool hasTemplate() @property
	{
		return hasTemplateParens || templateArgumentsRange != typeof(templateArgumentsRange).init;
	}

	/// Range starting before exclamation point until after closing bracket or before function opening bracket.
	int[2] templateArgumentsRange;
	///
	bool hasTemplateParens;
	///
	Argument[] templateArgs;
	/// Range starting before opening parentheses until after closing parentheses.
	int[2] functionParensRange;
	///
	Argument[] functionArgs;
	/// True if the function is UFCS or a member function of some object or namespace.
	/// False if this is a global function call.
	bool hasParent;
	/// Start of the function itself.
	int functionStart;
	/// Start of the whole call going up all call parents. (`foo.bar.function` having `foo.bar` as parents)
	int parentStart;
	/// True if cursor is in template parameters
	bool inTemplateParameters;
	/// Number of the active parameter (where the cursor is) or -1 if in none
	int activeParameter = -1;
}

extern(C) CalltipsSupport extractCallParameters(const(char)* code, size_t length, int position, bool definition)
{
	auto cache = StringCache(length.optimalBucketCount);
    LexerConfig config = LexerConfig("", StringBehavior.source);
	auto tokens = getTokensForParser(cast(ubyte[]) code[0 .. length], config, &cache);
	if (!tokens.length)
		return CalltipsSupport.init;

	if (tokens[0].type == tok!"(")
	{
		// add dummy name if we start with '('
		if (definition)
			tokens = [Token(tok!"void"), Token(tok!"identifier")] ~ tokens;
		else
			tokens = [Token(tok!"identifier")] ~ tokens;
	}

	// TODO: can probably use tokenIndexAtByteIndex here
	auto queuedToken = tokens.countUntil!(a => a.index >= position) - 1;
	if (queuedToken == -2)
		queuedToken = cast(ptrdiff_t) tokens.length - 1;
	else if (queuedToken == -1)
		return CalltipsSupport.init;

	// TODO: refactor code to be more readable
	// all this code does is:
	// - go back all tokens until a starting ( is found. (with nested {} scope checks for delegates and () for calls)
	//   - abort if not found
	//   - set "isTemplate" if directly before the ( is a `!` token and an identifier
	// - if inTemplate is true:
	//   - go forward to starting ( of normal arguments -- this code has checks if startParen is `!`, which currently can't be the case but might be useful
	// - else not in template arguments, so
	//   - if before ( comes a ) we are definitely in a template, so track back until starting (
	//   - otherwise check if it's even a template (single argument: `!`, then a token, then `(`)
	// - determine function name & all parents (strips out index operators)
	// - split template & function arguments
	// - return all information
	// it's reasonably readable with the variable names and that pseudo explanation there pretty much directly maps to the code,
	// so it shouldn't be too hard of a problem, it's just a lot return values per step and taking in multiple returns from previous steps.

	/// describes if the target position is inside template arguments rather than function arguments (only works for calls and not for definition)
	bool inTemplate;
	int depth, subDepth;
	/// contains opening parentheses location for arguments or exclamation point for templates.
	auto startParen = queuedToken;
	while (startParen >= 0)
	{
		const c = tokens[startParen];
		const p = startParen > 0 ? tokens[startParen - 1] : Token.init;

		if (c.type == tok!"{")
		{
			if (subDepth == 0)
			{
				// we went too far, probably not inside a function (or we are in a delegate, where we don't want calltips)
				return CalltipsSupport.init;
			}
			else
				subDepth--;
		}
		else if (c.type == tok!"}")
		{
			subDepth++;
		}
		else if (subDepth == 0 && c.type == tok!";")
		{
			// this doesn't look like function arguments anymore
			return CalltipsSupport.init;
		}
		else if (depth == 0 && !definition && c.type == tok!"!" && p.type == tok!"identifier")
		{
			inTemplate = true;
			break;
		}
		else if (c.type == tok!")")
		{
			depth++;
		}
		else if (c.type == tok!"(")
		{
			if (depth == 0 && subDepth == 0)
			{
				if (startParen > 1 && p.type == tok!"!" && tokens[startParen - 2].type
						== tok!"identifier")
				{
					startParen--;
					inTemplate = true;
				}
				break;
			}
			else
				depth--;
		}
		startParen--;
	}

	if (startParen <= 0)
		return CalltipsSupport.init;

	/// Token index where the opening template parentheses or exclamation point is. At first this is only set if !definition but later on this is resolved.
	auto templateOpen = inTemplate ? startParen : 0;
	/// Token index where the normal argument parentheses start or 0 if it doesn't exist for this call/definition
	auto functionOpen = inTemplate ? 0 : startParen;

	bool hasTemplateParens = false;

	if (inTemplate)
	{
		// go forwards to function arguments
		if (templateOpen + 2 < tokens.length)
		{
			if (tokens[templateOpen + 1].type == tok!"(")
			{
				hasTemplateParens = true;
				templateOpen++;
				functionOpen = findClosingParenForward(tokens, templateOpen,
						"in template function open finder");
				functionOpen++;

				if (functionOpen >= tokens.length)
					functionOpen = 0;
			}
			else
			{
				// single template arg (can only be one token)
				// https://dlang.org/spec/grammar.html#TemplateSingleArgument
				if (tokens[templateOpen + 2] == tok!"(")
					functionOpen = templateOpen + 2;
			}
		}
		else
			return CalltipsSupport.init; // syntax error
	}
	else
	{
		// go backwards to template arguments
		if (functionOpen > 0 && tokens[functionOpen - 1].type == tok!")")
		{
			// multi template args
			depth = 0;
			subDepth = 0;
			templateOpen = functionOpen - 1;
			const minTokenIndex = definition ? 1 : 2;
			while (templateOpen >= minTokenIndex)
			{
				const c = tokens[templateOpen];

				if (c == tok!")")
					depth++;
				else
				{
					if (depth == 1 && templateOpen > minTokenIndex && c.type == tok!"(")
					{
						if (definition
								? tokens[templateOpen - 1].type == tok!"identifier" : (tokens[templateOpen - 1].type == tok!"!"
									&& tokens[templateOpen - 2].type == tok!"identifier"))
							break;
					}

					if (depth == 0)
					{
						templateOpen = 0;
						break;
					}

					if (c == tok!"(")
						depth--;
				}

				templateOpen--;
			}

			if (templateOpen < minTokenIndex)
				templateOpen = 0;
			else
				hasTemplateParens = true;
		}
		else
		{
			// single template arg (can only be one token) or no template at all here
			if (functionOpen >= 3 && tokens[functionOpen - 2] == tok!"!"
					&& tokens[functionOpen - 3] == tok!"identifier")
			{
				templateOpen = functionOpen - 2;
			}
		}
	}

	depth = 0;
	subDepth = 0;
	bool inFuncName = true;
	auto callStart = (templateOpen ? templateOpen : functionOpen) - 1;
	auto funcNameStart = callStart;
	while (callStart >= 0)
	{
		const c = tokens[callStart];
		const p = callStart > 0 ? tokens[callStart - 1] : Token.init;

		if (c.type == tok!"]")
			depth++;
		else if (c.type == tok!"[")
		{
			if (depth == 0)
			{
				// this is some sort of `foo[(4` situation
				return CalltipsSupport.init;
			}
			depth--;
		}
		else if (c.type == tok!")")
			subDepth++;
		else if (c.type == tok!"(")
		{
			if (subDepth == 0)
			{
				// this is some sort of `foo((4` situation
				return CalltipsSupport.init;
			}
			subDepth--;
		}
		else if (depth == 0)
		{

			if (c.type.isCalltipable)
			{
				if (c.type == tok!"identifier" && p.type == tok!"." && (callStart < 2
						|| !tokens[callStart - 2].type.among!(tok!";", tok!",",
						tok!"{", tok!"}", tok!"(")))
				{
					// member function, traverse further...
					if (inFuncName)
					{
						funcNameStart = callStart;
						inFuncName = false;
					}
					callStart--;
				}
				else
				{
					break;
				}
			}
			else
			{
				// this is some sort of `4(5` or `if(4` situtation
				return CalltipsSupport.init;
			}
		}
		// we ignore stuff inside brackets and parens such as `foo[4](5).bar[6](a`
		callStart--;
	}

	if (inFuncName)
		funcNameStart = callStart;

	ptrdiff_t templateClose;
	if (templateOpen)
	{
		if (hasTemplateParens)
		{
			if (functionOpen)
				templateClose = functionOpen - 1;
			else
				templateClose = findClosingParenForward(tokens, templateOpen,
						"in template close finder");
		}
		else
			templateClose = templateOpen + 2;
	}
	//dfmt on
	auto functionClose = functionOpen ? findClosingParenForward(tokens,
			functionOpen, "in function close finder") : 0;

	CalltipsSupport.Argument[] templateArgs;
	if (templateOpen)
		templateArgs = splitArgs(tokens[templateOpen + 1 .. templateClose], true);

	CalltipsSupport.Argument[] functionArgs;
	if (functionOpen)
		functionArgs = splitArgs(tokens[functionOpen + 1 .. functionClose], false);

	int activeParameter = -1;
	foreach (i, arg; functionArgs)
	{
		if (arg.contentRange[0] <= position && arg.contentRange[1] >= position)
		{
			activeParameter = cast(int)i;
			break;
		}
		if (arg.contentRange[1] != 0 && arg.contentRange[1] < position)
			activeParameter = cast(int)i + 1;
	}

	return CalltipsSupport([
			tokens.tokenIndex(templateOpen),
			templateClose ? tokens.tokenEndIndex(templateClose) : 0
			], hasTemplateParens, templateArgs, [
			tokens.tokenIndex(functionOpen),
			functionClose ? tokens.tokenEndIndex(functionClose) : 0
			], functionArgs, funcNameStart != callStart, tokens.tokenIndex(funcNameStart),
			tokens.tokenIndex(callStart), inTemplate, activeParameter);
}



    /// Returns the index of the closing parentheses in tokens starting at the opening parentheses which is must be at tokens[open].
ptrdiff_t findClosingParenForward(const(Token)[] tokens, ptrdiff_t open, string what = null)
in(tokens[open].type == tok!"(",
		"Calling findClosingParenForward must be done on a ( token and not on a " ~ str(
			tokens[open].type) ~ " token! " ~ what)
{
	if (open >= tokens.length || open < 0)
		return open;

	open++;

	int depth = 1;
	int subDepth = 0;
	while (open < tokens.length)
	{
		const c = tokens[open];

		if (c == tok!"(" || c == tok!"[")
			depth++;
		else if (c == tok!"{")
			subDepth++;
		else if (c == tok!"}")
		{
			if (subDepth == 0)
				break;
			subDepth--;
		}
		else
		{
			if (c == tok!";" && subDepth == 0)
				break;

			if (c == tok!")" || c == tok!"]")
				depth--;

			if (depth == 0)
				break;
		}

		open++;
	}
	return open;
}

CalltipsSupport.Argument[] splitArgs(const(Token)[] tokens, bool templateArgs)
{
	auto ret = appender!(CalltipsSupport.Argument[]);
	size_t start = 0;
	size_t valueStart = 0;

	int depth, subDepth;
	const targetDepth = tokens.length > 0 && tokens[0].type == tok!"(" ? 1 : 0;
	bool gotValue;

	void putArg(size_t end)
	{
		if (start >= end || start >= tokens.length)
			return;

		CalltipsSupport.Argument arg;

		auto typename = tokens[start .. end];
		arg.contentRange = [cast(int) typename[0].index, typename[$ - 1].tokenEnd];

		if (gotValue && valueStart > start && valueStart <= end)
		{
			typename = tokens[start .. valueStart - 1];
			auto val = tokens[valueStart .. end];
			if (val.length)
				arg.valueRange = [cast(int) val[0].index, val[$ - 1].tokenEnd];
		}

		if (typename.length && typename[$ - 1].type == tok!"...")
		{
			arg.variadic = true;
			typename = typename[0 .. $ - 1];
		}

		if (typename.length)
		{
			if (typename.length >= 2 && typename[$ - 1].type == tok!"identifier")
			{
				arg.typeRange = [cast(int) typename[0].index, typename[$ - 2].tokenEnd];
				arg.nameRange = typename[$ - 1].tokenRange;
			}
			else
			{
				arg.typeRange = arg.nameRange = [cast(int) typename[0].index, typename[$ - 1].tokenEnd];
			}
		}

		ret.put(arg);

		gotValue = false;
		start = end + 1;
	}

	foreach (i, token; tokens)
	{
		if (token.type == tok!"{")
			subDepth++;
		else if (token.type == tok!"}")
		{
			if (subDepth == 0)
				break;
			subDepth--;
		}
		else if (token.type == tok!"(" || token.type == tok!"[")
			depth++;
		else if (token.type == tok!")" || token.type == tok!"]")
		{
			if (depth <= targetDepth)
				break;
			depth--;
		}

		if (depth == targetDepth)
		{
			if (token.type == tok!",")
				putArg(i);
			else if (token.type == tok!":" || token.type == tok!"=")
			{
				if (!gotValue)
				{
					valueStart = i + 1;
					gotValue = true;
				}
			}
		}
	}
	putArg(tokens.length);

	return ret.data;
}

int[2] tokenRange(const Token token)
{
	return [cast(int) token.index, cast(int)(token.index + token.tokenText.length)];
}

int tokenEnd(const Token token)
{
	return cast(int)(token.index + token.tokenText.length);
}

int tokenEnd(const Token[] token)
{
	if (token.length)
		return tokenEnd(token[$ - 1]);
	else
		return -1;
}

bool isCalltipable(IdType type)
{
	return type == tok!"identifier" || type == tok!"assert" || type == tok!"import"
		|| type == tok!"mixin" || type == tok!"super" || type == tok!"this" || type == tok!"__traits";
}

int tokenIndex(const(Token)[] tokens, ptrdiff_t i)
{
	if (i > 0 && i == tokens.length)
		return cast(int)(tokens[$ - 1].index + tokens[$ - 1].tokenText.length);
	return i >= 0 ? cast(int) tokens[i].index : 0;
}

int tokenEndIndex(const(Token)[] tokens, ptrdiff_t i)
{
	if (i > 0 && i == tokens.length)
		return cast(int)(tokens[$ - 1].index + tokens[$ - 1].text.length);
	return i >= 0 ? cast(int)(tokens[i].index + tokens[i].tokenText.length) : 0;
}

private enum dynamicTokens = [
		"specialTokenSequence", "comment", "identifier", "scriptLine",
		"whitespace", "doubleLiteral", "floatLiteral", "idoubleLiteral",
		"ifloatLiteral", "intLiteral", "longLiteral", "realLiteral",
		"irealLiteral", "uintLiteral", "ulongLiteral", "characterLiteral",
		"dstringLiteral", "stringLiteral", "wstringLiteral"
	];

string tokenText(const Token token)
{
	switch (token.type)
	{
		static foreach (T; dynamicTokens)
		{
	case tok!T:
		}
		return token.text;
	default:
		return str(token.type);
	}
}