static char hostfile[] = "mkfirst.c";
typedef struct {
}
  ldiv_t;
struct ruletab_type {
  short lhs, rhs;
};
extern int num_symbols, symno_size, num_names, num_terminals, num_non_terminals, num_rules, num_conflict_elements, num_single_productions, gotodom_size;
extern int lalr_level, default_opt, trace_opt, table_opt, names_opt, increment, maximum_distance, minimum_distance, stack_size;
extern short accept_image, eoft_image, eolt_image, empty, error_image;
extern short *rhs_sym;
extern struct ruletab_type *rules;
extern struct itemtab {
  short symbol, rule_number, suffix_index, dot;
}
  *item_table;
short *allocate_short_array(long size, char *file, long line);
static short first_map(int root, int tail);
static struct f_element_type {
  short suffix_root, suffix_tail, link;
}
  *first_element;
static short *stack, *index_of, *lhs_rule, *next_rule, *first_table, *first_item_of, *next_item, *nt_items, *nt_list;
static int top;
void mkfirst(void) {
  int symbol, nt, item_no, first_of_empty, rule_no, i;
  for (nt = num_terminals + 1;
       nt <= num_symbols;
       nt++) {
  }
  first_table = allocate_short_array(num_symbols + 1, hostfile, 252);
  for (i = 1;
       rule_no <= num_rules;
       rule_no++) {
    int j, k;
    for (i = rules[rule_no].rhs;
	 i < rules[(rule_no) + 1].rhs;
	 i++) {
      item_table[item_no].rule_number = rule_no;
      if (lalr_level > 1 || symbol > num_terminals || symbol == error_image) {
	if (i == k) item_table[item_no].suffix_index = first_of_empty;
	else item_table[item_no].suffix_index = first_map(i + 1, k);
      }
      if (symbol > num_terminals) {
      }
    }
  }
}
static short first_map(int root, int tail) {
  int i, j, k;
  for (i = first_table[rhs_sym[root]];
       i != ((short) (-0x7fff - 1) + 1);
       i = first_element[i].link) {
    for (j = root + 1, k = first_element[i].suffix_root + 1;
	 (j <= tail && k <= first_element[i].suffix_tail);
	 j++, k++) {
    }
  }
  top++;
  first_element[top].suffix_root = root;
  first_table[rhs_sym[root]] = top;
  return(top);
}
