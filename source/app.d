import std.stdio;
import std.file;
import std.conv;

import parser;
import lexer;
import token;
import skolemize;
import model;
import std.string;

void main()
{
	string f = cast(string)read("input.txt");
	auto lexer = new Lexer(f);
	auto parser = Parser(lexer.tokenize());
	auto ast = parser.parse();
	writeToFile("ast.txt", ast);

	auto sAST = *(skolemizeNode(ast));

	writeToFile("skolemized_ast.txt", &sAST);

	writeln(toFormulaString(&sAST));	
}

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
				result ~= "A";
				break;
			case NodeType.Existential:
				result ~= "E";
				break;
			case NodeType.Variable:
				result ~= node.value;
				break;
			case NodeType.Predicate:
				result ~= node.value;
				break;
			default:
				break;
		}
		result ~= toFormulaString(node.left);
		result ~= toFormulaString(node.right);
	}

	return result;
}

void writeToFile(string filename, ASTNode* node)
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