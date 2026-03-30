module skolemizer;

import std.stdio;
import std.file;
import std.string;
import std.algorithm.searching;

public import skolemizer.lexer;
public import skolemizer.parser;
public import skolemizer.skolemize;
public import skolemizer.model;
public import skolemizer.token;

/// Skolemize a formula given as a string
public ASTNode* parseFormula(string input) {
    auto tokens = tokenize(input);
    return parse(tokens);
}

/// Skolemize a formula given as a string
public ASTNode* skolemizeFormula(string input) {
    auto tokens = tokenize(input);
    auto ast = parse(tokens);
    return skolemizeNode(ast);
}

/// Skolemize a formula given as an AST
public ASTNode* skolemizeFormula(ASTNode* ast) {
    return skolemizeNode(ast);
}

/// Write AST to a file with indentation
public void writeToFile(string filename, ASTNode* node)
{
	auto file = File(filename, "w");
	scope(exit) file.close();
	string content = node.toString();
	int depth = 0;
	char prev = '\0';
	foreach (c; content) {
		if (prev == '[') {
			depth++;
			file.write('\n');
			for (int i = 0; i < depth; i++) {
				file.write("\t");
			}
		} else if (c == ']') {
			depth--;
			file.write('\n');
			for (int i = 0; i < depth; i++) {
				file.write("\t");
			}
		}
		file.write(c);
		prev = c;
	}
}

/// Convert AST to a human-readable formula string
dstring toFormulaString(ASTNode* node, dstring result = "")
{
	if (node is null) {
		return "";
	}

	if (node.type == NodeType.Conjunction || node.type == NodeType.Disjunction || 
		node.type == NodeType.Implication || node.type == NodeType.Biconditional) {
		
		result ~= "(";
		result ~= toFormulaString(node.left);
		switch (node.type)
		{
			case NodeType.Conjunction:  result ~= " and "; break;
			case NodeType.Disjunction:  result ~= " or "; break;
			case NodeType.Implication:  result ~= "->"; break;
			case NodeType.Biconditional: result ~= "<->"; break;
			default: break;
		}
		result ~= toFormulaString(node.right);
		result ~= ")";
	} else {
		switch (node.type)
		{
			case NodeType.Negation:
				result ~= " not ";
				break;
			case NodeType.Universal:
				result ~= "A"d~node.value;
				break;
			case NodeType.Existential:
				result ~= "E"d~node.value;
				break;
			case NodeType.Variable:
				result ~= node.value;
				break;
			case NodeType.Predicate:
				dstring argsStr;
				foreach (arg; node.args) {
					argsStr ~= toFormulaString(arg) ~ ", ";
				}
				// remove trailing comma and space
				if (argsStr.length >= 2) {
					argsStr = argsStr[0 .. $ - 2];
				}
				result ~= node.value ~ "(" ~ argsStr ~ ")";
				break;
			case NodeType.SkolemFunction:
				dstring skolemArgsStr;
				foreach (arg; node.args) {
					skolemArgsStr ~= toFormulaString(arg) ~ ", ";
				}
				// remove trailing comma and space
				if (skolemArgsStr.length >= 2) {
					skolemArgsStr = skolemArgsStr[0 .. $ - 2];
				}
				result ~= node.value ~ "(" ~ skolemArgsStr ~ ")";
				break;
			case NodeType.Function:
				dstring funcArgsStr;
				foreach (arg; node.args) {
					funcArgsStr ~= toFormulaString(arg) ~ ", ";
				}
				if (funcArgsStr.length >= 2) {
					funcArgsStr = funcArgsStr[0 .. $ - 2];
				}
				result ~= node.value ~ "(" ~ funcArgsStr ~ ")";
				break;
			default:
				break;
		}
		result ~= toFormulaString(node.left);
		result ~= toFormulaString(node.right);
	}

	if (result.length < 2) {
		return result;
	}

	// remove leading and trailing parenthesis
	int depth = 0;
	while (result[depth] == '(')
	{
		depth++;
	}

	result = result[depth..result.length-depth];

	// remove all double spaces
	while (result.canFind("  "d))
	{
		result = result.replace("  "d, " "d);
	}

	// remove trailing and tailing spaces
	result = result.strip();

	return result;
}

unittest {
	string formula = "AxEyAzEw(P(s(x)) > (P(y)&P(w) > !P(s(z)))))";
	dstring skolemized = toFormulaString(skolemizeFormula(formula));
	assert(skolemized == "not P(s(v0)) or not P(f0(v0)) or not P(f1(v0, v2)) or not P(s(v2))");
}