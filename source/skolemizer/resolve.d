module skolemizer.resolve;

import skolemizer.model;
import skolemizer.parser;
import skolemizer.skolemize;

import std.stdio;
import std.format;
import std.sumtype;

// result sumtype

enum DPLLResult { Satisfiable = "Satisfiable", Unsatisfiable = "Unsatisfiable", Unknown = "Unknown" }


// https://en.wikipedia.org/wiki/DPLL_algorithm
DPLLResult DPLL(ASTNode*[hash_t][hash_t] clauses)
{
    int numTries = 0;
    while (true) {
        if (numTries > 1_000) {
            return DPLLResult.Unknown;
        }

        // look for unit clauses
        foreach (key, clause; clauses) {
            if (clause.length == 1) {
                // found a unit clause, assign the variable and simplify
                auto unit = *clause.values[0];
                writeln("Found unit clause: " ~ toFormulaString(&unit));
            }
        }

        foreach (key, clause; clauses) {
            if (clause.length == 0) {
                return DPLLResult.Unsatisfiable;
            }
        }

        numTries++;
    }
    return DPLLResult.Satisfiable;
}





public ASTNode*[hash_t][hash_t] toDisjunctForm(ASTNode* node)
{
    node = skolemizeNode(node);
    writeToFile("skolemized.txt", node);
    node = distribute(node);
    writeToFile("distributed.txt", node);
    
    writeln("Distributed: " ~ toFormulaString(node));

    // hashset workaround using an associative array
    ASTNode*[hash_t] clauses;
    splitOnConj(node, clauses);
    ASTNode*[hash_t][hash_t] disjunctClauses;
    foreach (hash, clause; clauses) {
        ASTNode*[hash_t] disjunctSet;
        splitOnDisj(clause, disjunctSet);
        disjunctClauses[hash] = disjunctSet;
    }
    return disjunctClauses;
}

ASTNode* distribute(ASTNode* node) {
    if (node is null) return null;

    if (node.type == NodeType.Conjunction) {
        node.left = distribute(node.left);
        node.right = distribute(node.right);
        return node;
    }

    if (node.type == NodeType.Disjunction) {
        auto l = distribute(node.left);
        auto r = distribute(node.right);

        if (l.type == NodeType.Conjunction)
            return distribute(new ASTNode(
                NodeType.Conjunction,
                null,
                distribute(new ASTNode(NodeType.Disjunction, null, l.left, cloneAST(r))),
                distribute(new ASTNode(NodeType.Disjunction, null, l.right, cloneAST(r)))
            ));

        if (r.type == NodeType.Conjunction)
            return distribute(new ASTNode(
                NodeType.Conjunction,
                null,
                distribute(new ASTNode(NodeType.Disjunction, null, cloneAST(l), r.left)),
                distribute(new ASTNode(NodeType.Disjunction, null, cloneAST(l), r.right))
            ));

        node.left = l;
        node.right = r;
        return node;
    }

    return node;
}

private void splitOnDisj(ASTNode* node, ref ASTNode*[hash_t] disjuncts)
{
    if (node is null) return;

    if (node.type == NodeType.Disjunction) {
        splitOnDisj(node.left, disjuncts);
        splitOnDisj(node.right, disjuncts);
    } else {
        auto hash = hashOfASTNode(node);
        disjuncts[hash] = node;
    }
}

private void splitOnConj(ASTNode* node, ref ASTNode*[hash_t] clauses)
{
    if (node is null) return;

    if (node.type == NodeType.Conjunction) {
        splitOnConj(node.left, clauses);
        splitOnConj(node.right, clauses);
    } else {
        auto hash = hashOfASTNode(node);
        clauses[hash] = node;
    }
}

dstring toSetString(ASTNode*[hash_t][hash_t] set)
{
	dstring result;
	result ~= "{\n";
	foreach (key, value; set) {
        result ~= "\t{\n";
        result ~= "\t\t";
		foreach (clause; value) {
			result ~= toFormulaString(clause) ~ ", ";
		}
        // remove trailing comma and newline
        if (result.length >= 2) {
            result = result[0 .. $ - 2];
        }
        result ~= "\n\t}\n";
	}
	result ~= "}";
	return result;
}

unittest
{

}
