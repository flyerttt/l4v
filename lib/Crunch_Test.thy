(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(NICTA_BSD)
 *)


theory Crunch_Test (* FIXME: not tested *)
imports Crunch Crunch_Test_Qualified GenericLib Defs
begin

text {* Test cases for crunch *}

definition
  "crunch_foo1 (x :: nat) \<equiv> do
    modify (op + x);
    modify (op + x)
  od"

definition
  "crunch_foo2 \<equiv> do
    crunch_foo1 12;
    crunch_foo1 13
  od"

crunch (empty_fail) empty_fail: crunch_foo2
(ignore: modify bind)

crunch_ignore (add: crunch_foo1)

crunch gt: crunch_foo2 "\<lambda>x. x > y"
  (ignore: modify bind ignore_del: crunch_foo1)

crunch_ignore (del: crunch_foo1)

definition
  "crunch_always_true (x :: nat) \<equiv> \<lambda>y :: nat. True"

lemma crunch_foo1_at_2:
  "\<lbrace>crunch_always_true 2 and crunch_always_true 3\<rbrace>
      crunch_foo1 x \<lbrace>\<lambda>rv. crunch_always_true 2\<rbrace>"
  by (simp add: crunch_always_true_def, wp)

lemma crunch_foo1_at_3[wp]:
  "\<lbrace>crunch_always_true 3\<rbrace> crunch_foo1 x \<lbrace>\<lambda>rv. crunch_always_true 3\<rbrace>"
  by (simp add: crunch_always_true_def, wp)

lemma crunch_foo1_no_fail:
  "no_fail (crunch_always_true 2 and crunch_always_true 3) (crunch_foo1 x)"
  apply (simp add:crunch_always_true_def crunch_foo1_def)
  apply (rule no_fail_pre)
   apply (wp, simp)
  done

crunch (no_fail) no_fail: crunch_foo2
(ignore: modify bind wp: crunch_foo1_at_2)

crunch (valid) at_2: crunch_foo2 "crunch_always_true 2"
  (ignore: modify bind wp: crunch_foo1_at_2)

fun crunch_foo3 :: "nat => nat => 'a => (nat,unit) nondet_monad" where
  "crunch_foo3 0 x _ = crunch_foo1 x"
| "crunch_foo3 (Suc n) x y = crunch_foo3 n x y"

crunch gt2: crunch_foo3 "\<lambda>x. x > y"
  (ignore: modify bind)

crunch (empty_fail) empty_fail2: crunch_foo3
  (ignore: modify bind)

class foo_class = 
  fixes stuff :: 'a
begin

fun crunch_foo4 :: "nat => nat => 'a => (nat,unit) nondet_monad" where
  "crunch_foo4 0 x _ = crunch_foo1 x"
| "crunch_foo4 (Suc n) x y = crunch_foo4 n x y"

definition
  "crunch_foo5 x y \<equiv> crunch_foo1 x"

end

lemma crunch_foo4_alt:
  "crunch_foo4 n x y \<equiv> crunch_foo1 x"
  apply (induct n)
   apply simp+
  done

(* FIXME: breaks, does not find induct_instance, wrong number of params
crunch gt3: crunch_foo4 "\<lambda>x. x > y"
  (ignore: modify bind)
*)

crunch (no_fail) no_fail2: crunch_foo4
  (unfold: "(crunch_foo4, crunch_foo4_alt)" ignore: modify bind)

crunch gt3: crunch_foo4 "\<lambda>x. x > y"
  (unfold: "(crunch_foo4, crunch_foo4_alt)" ignore: modify bind)

crunch gt4: crunch_foo5 "\<lambda>x. x > y"
  (ignore: modify bind)

(* Test cases for crunch in locales *)

crunch_ignore (add: bind)

definition
  "crunch_foo6 \<equiv> return () >>= (\<lambda>_. return ())"

locale test_locale =
fixes fixed_return_unit :: "(unit, unit) nondet_monad"

begin

definition
  "crunch_foo7 \<equiv> return () >>= (\<lambda>_. return ())"

(* crunch works on a global constant within a locale *)
crunch test[wp]: crunch_foo6 P

(* crunch works on a locale constant *)
crunch test[wp]: crunch_foo7 P

definition
  "crunch_foo8 \<equiv> fixed_return_unit >>= (\<lambda>_. fixed_return_unit)"

definition
  "crunch_foo9 (x :: nat) \<equiv> do
    modify (op + x);
    modify (op + x)
  od"

crunch test[wp]: crunch_foo9 "\<lambda>x. x > y" (ignore: modify)

definition
  "crunch_foo10 (x :: nat) \<equiv> do
    modify (op + x);
    modify (op + x)
  od"

(*crunch_def attribute overrides definition lookup *)

lemma crunch_foo10_def2[crunch_def]:
  "crunch_foo10 = crunch_foo9"
  unfolding crunch_foo10_def[abs_def] crunch_foo9_def[abs_def]
  by simp

crunch test[wp]: crunch_foo10 "\<lambda>x. x > y"

(* crunch_ignore works within a locale *)
crunch_ignore (add: modify)

crunch test[wp]: crunch_foo9 "\<lambda>x. x > y"

end

interpretation test_locale "return ()" .

(* interpretation promotes the wp attribute from the locale *)
lemma "\<lbrace>Q\<rbrace> crunch_foo7 \<lbrace>\<lambda>_. Q\<rbrace>" by wp

(* crunch still works on an interpreted locale constant *)
crunch test2: crunch_foo7 P

locale test_sublocale

sublocale test_sublocale < test_locale "return ()" .

context test_sublocale begin

(* crunch works on a locale constant with a fixed locale parameter *)
crunch test[wp]: crunch_foo8 P

end

(* check that qualified names are handled properly. *)

consts foo_const :: "(unit, unit) nondet_monad"
defs foo_const_def: "foo_const \<equiv> Crunch_Test_Qualified.foo_const"

crunch test: foo_const P

end
