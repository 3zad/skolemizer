import std.stdio;
import std.file;
import std.conv;

import parser;
import lexer;
import token;
import skolemize;
import model;

void main()
{
	string f = cast(string)read("input.txt");
	auto lexer = new Lexer(f);
	auto parser = Parser(lexer.tokenize());
	auto ast = parser.parse();
	writeToFile("ast.txt", ast);

	writeln(*(skolemizeNode(ast)));
	writeToFile("skolemized_ast.txt", skolemizeNode(ast));
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