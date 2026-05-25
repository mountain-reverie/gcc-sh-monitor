static char hostfile[] = "remsp.c";
typedef char BOOLEAN;
struct shift_type {
  short symbol, action;
};
struct shift_header_type {
  struct shift_type *map;
  short size;
};
struct goto_type {
  short symbol, action;
};
struct goto_header_type {
  struct goto_type *map;
  short size;
};
struct statset_type {
  struct goto_header_type go_to;
  short shift_number;
};
extern int num_symbols, symno_size, num_names, num_terminals, num_non_terminals, num_rules, num_conflict_elements, num_single_productions, gotodom_size;
extern long string_offset, string_size, num_shifts, num_shift_reduces, num_gotos, num_goto_reduces, num_reductions, num_sr_conflicts, num_rr_conflicts, num_entries;
extern struct shift_header_type *shift;
extern struct statset_type *statset;
short *allocate_short_array(long size, char *file, long line);
static struct action_element {
  struct action_element *next;
  short symbol, action;
}
  **new_action;
static struct update_action_element {
}
  **update_action;
static short *sp_rules, *stack, *index_of, *next_rule, *rule_list, **sp_action;

void remove_single_productions(void) {
  struct goto_header_type go_to;
  struct shift_header_type sh;
  int rule_head, sp_rule_count, sp_action_count, rule_no, state_no, symbol, lhs_symbol, action, item_no, i, j;
  short *symbol_list, *shift_transition, *rule_count;
  short shift_table[(400 + 1)];
  struct new_shift_element {
    short link, shift_number;
  }
    *new_shift;
  shift_transition = allocate_short_array(num_symbols + 1, hostfile, 807);
  for (i = 0;
       i <= num_rules;
       state_no++) {
    BOOLEAN any_shift_action;
    if (new_action[state_no] != ((void *)0) ) {
      struct action_element *p;
      go_to = statset[state_no].go_to;
      for (i = 1;
	   i <= go_to.size;
	   i++) index_of[(((go_to).map)[i].symbol)] = i;
      sh = shift[statset[state_no].shift_number];
      for (i = 1;
	   i <= sh.size;
	   i++) {
	shift_transition[(((sh).map)[i].symbol)] = (((sh).map)[i].action);
      }
      for (p = new_action[state_no];
	   p != ((void *)0) ;
	   p = p -> next) {
	if (p -> symbol > num_terminals) {
	  if ((((go_to).map)[index_of[p -> symbol]].action) < 0 && p -> action > 0) {
	    num_goto_reduces--;
	  }
	}
      }
      if (any_shift_action) {
	struct shift_header_type sh2;
	unsigned long hash_address;
	for (j = shift_table[hash_address];
	     j != ((short) (-0x7fff - 1) + 1);
	     j = new_shift[j].link) {
	  if (sh.size == sh2.size) {
	    for (i = 1;
		 i <= sh.size;
		 i++) if ((((sh2).map)[i].action) != shift_transition[(((sh2).map)[i].symbol)]) break;
	  }
	}
	if (j == ((short) (-0x7fff - 1) + 1)) {
	  for (i = 1;
	       i <= sh.size;
	       i++) {
	  }
	}
      }
    }
  }
}
