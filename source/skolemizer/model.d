module skolemizer.model;

import std.string : format;

import std.algorithm;
import std.array;

public enum NodeType 
{ 
    Negation = "Negation", 
    Universal = "Universal", 
    Existential = "Existential", 
    Conjunction = "Conjunction", 
    Disjunction = "Disjunction", 
    Implication = "Implication", 
    Biconditional = "Biconditional", 
    Variable = "Variable",
    Constant = "Constant",
    Predicate = "Predicate",
    Function = "Function", 
    SkolemFunction = "SkolemFunction" 
}


public struct ASTNode {
    NodeType type;
    dstring value;
    ASTNode* left;
    ASTNode* right;
    ASTNode*[] args; // for predicates and Skolem functions

    public string toString() const {
        if (type == NodeType.Variable) {
            return format("ASTNode[ type: %s, value: %s ]", type, value);
        } else if (type == NodeType.Predicate || type == NodeType.SkolemFunction || type == NodeType.Function) {
            string argsStr;
            foreach (arg; args) {
                argsStr ~= arg.toString() ~ ", ";
            }
            return format("ASTNode[ type: %s, value: %s, args: [%s] ]", type, value, argsStr);
        } else if (type == NodeType.Negation) {
            return format("ASTNode[ type: %s, operand: %s ]", type, left.toString());
        } else if (type == NodeType.Universal || type == NodeType.Existential) {
            return format("ASTNode[ type: %s, variable: %s, body: %s ]", type, value, left.toString());
        } else {
            return format("ASTNode[ type: %s, left: %s, right: %s ]", type, left.toString(), right.toString());
        }
    }
}

private hash_t hashCombine(hash_t seed, hash_t value) {
    // fewer collisions compared to a simple XOR
    return seed ^ (value + 0x9e3779b9 + (seed << 6) + (seed >> 2));
}

public hash_t hashOfASTNode(const ASTNode* node) {
    if (node is null) return 0;

    hash_t h = 0;
    h = hashCombine(h, node.type.hashOf());
    h = hashCombine(h, node.value.hashOf());
    h = hashCombine(h, hashOfASTNode(node.left));
    h = hashCombine(h, hashOfASTNode(node.right));

    foreach (arg; node.args) {
        h = hashCombine(h, hashOfASTNode(arg));
    }

    return h;
}

public bool opEqualsASTNode(const ASTNode* a, const ASTNode* b) {
    if (a is null || b is null) return a is b;

    if (a.type != b.type) return false;
    if (a.value != b.value) return false;

    if (!opEqualsASTNode(a.left, b.left)) return false;
    if (!opEqualsASTNode(a.right, b.right)) return false;

    if (a.args.length != b.args.length) return false;
    foreach (i; 0 .. a.args.length) {
        if (!opEqualsASTNode(a.args[i], b.args[i])) return false;
    }

    return true;
}

public ASTNode* cloneAST(const ASTNode* node) {
    if (node is null) return null;

    auto copy = new ASTNode(node.type, node.value);
    copy.left = cloneAST(node.left);
    copy.right = cloneAST(node.right);
    copy.args = node.args.map!(arg => cloneAST(arg)).array;
    return copy;
}

unittest
{
    // check the correctness of hashOfASTNode and opEqualsASTNode
    auto node1 = new ASTNode(NodeType.Variable, "x");
    auto node2 = new ASTNode(NodeType.Variable, "x");
    auto node3 = new ASTNode(NodeType.Variable, "y");
    assert(opEqualsASTNode(node1, node2));
    assert(!opEqualsASTNode(node1, node3));
    assert(hashOfASTNode(node1) == hashOfASTNode(node2));
    assert(hashOfASTNode(node1) != hashOfASTNode(node3));

    auto node4 = new ASTNode(NodeType.Conjunction, "", node1, node3);
    auto node5 = new ASTNode(NodeType.Conjunction, "", node2, node3);
    assert(opEqualsASTNode(node4, node5));
    assert(hashOfASTNode(node4) == hashOfASTNode(node5));

    auto node6 = new ASTNode(NodeType.Conjunction, "", node1, node1);
    assert(!opEqualsASTNode(node4, node6));
    assert(hashOfASTNode(node4) != hashOfASTNode(node6));

    auto node7 = new ASTNode(NodeType.Predicate, "P");
    node7.args ~= node1;
    auto node8 = new ASTNode(NodeType.Predicate, "P");
    node8.args ~= node2;
    assert(opEqualsASTNode(node7, node8));
    assert(hashOfASTNode(node7) == hashOfASTNode(node8));

    // a and not a
    auto node9 = new ASTNode(NodeType.Negation, "", new ASTNode(NodeType.Variable, "a"), null);
    auto node10 = new ASTNode(NodeType.Variable, "a");
    assert(!opEqualsASTNode(node9, node10));
    assert(hashOfASTNode(node9) != hashOfASTNode(node10));

    auto node11 = new ASTNode(NodeType.Conjunction, "", node9, node9);
    auto node12 = new ASTNode(NodeType.Conjunction, "", node10, node10);
    assert(!opEqualsASTNode(node11, node12));
    assert(hashOfASTNode(node11) != hashOfASTNode(node12));
}