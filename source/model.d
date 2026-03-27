module model;

// Add more later
public enum NodeType { Negation, Conjunction, Disjunction, Implication, Biconditional, Variable }

public struct ASTNode {
    NodeType type;
    dstring value;
    ASTNode* left;
    ASTNode* right;

    public string toString() const {
        import std.string : format;
        if (type == NodeType.Variable) {
            return format("ASTNode[ type: %s, value: %s ]", type, value);
        } else if (type == NodeType.Negation) {
            return format("ASTNode[ type: %s, operand: %s ]", type, left.toString());
        }
        else {
            return format("ASTNode[ type: %s, left: %s, right: %s ]", type, left.toString(), right.toString());
        }
    }
}