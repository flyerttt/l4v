(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(NICTA_GPL)
 *)

theory Retype_AC
imports CNode_AC
begin

context begin interpretation Arch . (*FIXME: arch_split*)

(* put in here that we own the region mentioned in the invocation *)
definition
  authorised_untyped_inv :: "'a PAS \<Rightarrow> Invocations_A.untyped_invocation \<Rightarrow> bool"
where
 "authorised_untyped_inv aag ui \<equiv> case ui of
     Invocations_A.untyped_invocation.Retype src_slot base aligned_free_ref new_type obj_sz slots \<Rightarrow>
       is_subject aag (fst src_slot) \<and> (0::word32) < of_nat (length slots) \<and>
       (\<forall>x\<in>{aligned_free_ref..aligned_free_ref + of_nat (length slots)*2^(obj_bits_api new_type obj_sz) - 1}. is_subject aag x) \<and>
       new_type \<noteq> ArchObject ASIDPoolObj \<and>
       (\<forall>x\<in>set slots. is_subject aag (fst x))"

definition
  authorised_untyped_inv_state :: "'a PAS \<Rightarrow> Invocations_A.untyped_invocation \<Rightarrow> 'z::state_ext state \<Rightarrow> bool"
where
 "authorised_untyped_inv_state aag ui s \<equiv> case ui of
     Invocations_A.untyped_invocation.Retype src_slot base aligned_free_ref new_type obj_sz slots \<Rightarrow>
       (\<forall> cap. cte_wp_at (op = cap) src_slot s \<longrightarrow>
         (\<forall> x\<in>ptr_range base (bits_of cap). is_subject aag x))"

subsection{* invoke *}



lemma create_cap_integrity:
  "\<lbrace>integrity aag X st and K (is_subject aag (fst (fst ref)))\<rbrace>
     create_cap tp sz p ref
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply (simp add: create_cap_def split_def)
  apply (wp set_cap_integrity_autarch[unfolded pred_conj_def K_def]
            create_cap_extended.list_integ_lift
            create_cap_list_integrity
            set_original_integrity_autarch
              | simp add: set_cdt_def)+
  apply (simp add: integrity_def)
  apply (clarsimp simp: integrity_cdt_def)
  done

crunch inv[wp]: reserve_region P

lemma mol_respects:
  "\<lbrace>\<lambda>ms. integrity aag X st (s\<lparr>machine_state := ms\<rparr>)\<rbrace> machine_op_lift mop \<lbrace>\<lambda>a b. integrity aag X st (s\<lparr>machine_state := b\<rparr>)\<rbrace>"
  unfolding machine_op_lift_def
  apply (simp add: machine_rest_lift_def split_def)
  apply wp
  apply (clarsimp simp: integrity_def)
  done

lemma ptr_range_memI:
  "is_aligned p n \<Longrightarrow> p \<in> ptr_range p n"
  unfolding ptr_range_def
  apply (erule is_aligned_get_word_bits)
  apply (drule (1) base_member_set)
  apply (simp add: field_simps)
  apply simp
  done

lemma ptr_range_add_memI:
  "\<lbrakk> is_aligned (p :: 'a :: len word) n; k < 2 ^ n \<rbrakk> \<Longrightarrow> (p + k) \<in> ptr_range p n"
  unfolding ptr_range_def
  apply (erule is_aligned_get_word_bits)
  apply clarsimp
  apply (rule conjI)
   apply (erule (1) is_aligned_no_wrap')
  apply (subst p_assoc_help, rule word_plus_mono_right)
  apply simp
  apply (erule is_aligned_no_overflow')
  apply (subgoal_tac "2 ^ n = (0 :: 'a word)")
   apply simp
  apply (simp add: word_bits_conv)
  done

lemma storeWord_integrity_autarch:
  "\<lbrace>\<lambda>ms. integrity aag X st (s\<lparr>machine_state := ms\<rparr>) \<and> (is_aligned p 2 \<longrightarrow> (\<forall>p' \<in> ptr_range p 2. is_subject aag p'))\<rbrace> storeWord p v \<lbrace>\<lambda>a b. integrity aag X st (s\<lparr>machine_state := b\<rparr>)\<rbrace>"
  unfolding storeWord_def
  apply wp
  apply (auto simp: integrity_def is_aligned_mask [symmetric] intro!: trm_lrefl ptr_range_memI ptr_range_add_memI)
  done

lemma word_minus_1:
  "x + (0xFFFFFFFF::word32) = x - 1"
  by simp

lemma Suc_0_lt_cases:
  "\<lbrakk>(x = 0 \<Longrightarrow> False); (x = 1 \<Longrightarrow> False)\<rbrakk> \<Longrightarrow> Suc 0 < x"
  apply (rule classical)
  apply (auto simp add: not_less le_Suc_eq)
  done

lemmas upto_enum_step_shift_red =
   upto_enum_step_shift_red[where 'a=32, simplified, simplified word_bits_def[symmetric, simplified]]

lemma clearMemory_respects:
  "\<lbrace>\<lambda> a. integrity aag X st (s\<lparr>machine_state := a\<rparr>) \<and>
         is_aligned ptr sz \<and> sz < word_bits \<and> 2 \<le> sz \<and>
         (\<forall> y\<in>ptr_range ptr sz. is_subject aag y)\<rbrace>
    clearMemory ptr (2 ^ sz)
   \<lbrace>\<lambda>rv a. integrity aag X st (s\<lparr>machine_state := a\<rparr>)\<rbrace>"
  unfolding clearMemory_def
  apply (rule hoare_pre)
   apply (simp add: split_def cleanCacheRange_PoU_def)
   apply wp
   apply (simp add: cleanByVA_PoU_def)
   apply (wp mol_respects)
   apply (rule_tac Q="\<lambda> x ms. integrity aag X st (s\<lparr>machine_state := ms\<rparr>) \<and> (\<forall> y\<in> set [ptr , ptr + 4 .e. ptr + of_nat (2 ^ sz) - 1]. (is_aligned y 2 \<longrightarrow> (\<forall> z \<in> ptr_range y 2. is_subject aag z)))" in  hoare_strengthen_post)
    apply(wp mapM_x_wp' storeWord_integrity_autarch | simp add: no_irq_storeWord word_size_def)+
  apply(clarsimp simp: upto_enum_step_shift_red[where us=2, simplified])
  apply(erule bspec)
  apply(erule subsetD[rotated])
  apply(rule ptr_range_subset)
     apply assumption
    apply(rule is_aligned_mult_triv2[where n=2, simplified])
   apply assumption
  apply (auto simp: word_bits_def
             intro: word_less_power_trans_ofnat[where k=2, simplified])
  done



lemma create_word_objects_integrity:
  notes atLeastatMost_subset_iff[simp del]
  notes of_nat_diff[simp del]
  shows  "\<lbrace>integrity aag X st and
    K (range_cover ptr sz bits numObjects \<and>
       of_nat numObjects > (0::word32) \<and> bits \<ge> 2 \<and>
       (\<forall>y\<in>{ptr..ptr + (of_nat numObjects)*(2^bits) - 1}. is_subject aag y)) \<rbrace>
     create_word_objects ptr numObjects bits
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply(simp add: create_word_objects_def do_machine_op_def)
  apply (wp, simp add: split_def, wp modify_wp)
  apply clarify
  apply (erule use_valid)
  apply (wp mapM_x_wp' clearMemory_respects | simp)+
   prefer 2
   apply (clarsimp)
  apply clarify
  apply(rule conjI)
   apply(rule is_aligned_add)
    apply(simp add: range_cover_def)
   apply(rule is_aligned_shift)
  apply(rule conjI)
   apply(simp add: range_cover_def word_bits_def)
  apply(clarsimp)
  apply(erule bspec)
  apply(rule subsetD)
   apply(rule_tac p="unat n" in range_cover_subset)
     apply assumption
    apply(rule unat_less_helper)
    apply(rule minus_one_helper5)
     apply simp
    apply assumption
   apply(simp, rule_tac 'a=word32 in of_nat_gt_0)
   apply simp
  apply(simp add: shiftl_t2n ptr_range_def mult.commute)
  done

crunch integrity_autarch: set_pd "integrity aag X st"
  (wp: crunch_wps simp: crunch_simps)

lemma store_pde_integrity:
  "\<lbrace>integrity aag X st and K (is_subject aag (p && ~~ mask pd_bits))\<rbrace>
     store_pde p pde
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply(simp add: store_pde_def)
  apply(wp set_pd_integrity_autarch)
  apply(auto)
  done

(* Borrowed from part of copy_global_mappings_nonempty_table in Untyped_R.thy *)
lemma copy_global_mappings_index_subset:
  "set [kernel_base >> 20.e.2 ^ (pd_bits - 2) - 1] \<subseteq> {x. \<exists>y. x = y >> 20}"
  apply clarsimp
  apply (rule_tac x="x << 20" in exI)
  apply (subst shiftl_shiftr1, simp)
  apply (simp add: word_size)
  apply (rule sym, rule less_mask_eq)
  apply (simp add: minus_one_helper5 pd_bits_def pageBits_def)
  done

lemma copy_global_mappings_integrity:
  "is_aligned x pd_bits \<Longrightarrow>
   \<lbrace>integrity aag X st and K (is_subject aag x)\<rbrace>
     copy_global_mappings x
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (simp add: copy_global_mappings_def)
  apply (wp mapM_x_wp[OF _ subset_refl] store_pde_integrity)
  apply (drule subsetD[OF copy_global_mappings_index_subset])
   apply (fastforce simp: pd_shifting')
  apply(wp)
  done

lemma dmo_mol_respects:
  "\<lbrace>integrity aag X st\<rbrace> do_machine_op (machine_op_lift mop) \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  unfolding do_machine_op_def
  apply (simp add: split_def)
  apply wp
  apply clarsimp
  apply (erule use_valid)
  apply (wp mol_respects)
  apply simp
  done

lemma dmo_bind_valid:
  "\<lbrace>P\<rbrace> do_machine_op (a >>= b) \<lbrace>Q\<rbrace> = \<lbrace>P\<rbrace> do_machine_op a >>= (\<lambda>rv. do_machine_op (b rv)) \<lbrace>Q\<rbrace>"
  by (fastforce simp: do_machine_op_def gets_def get_def select_f_def modify_def put_def return_def bind_def valid_def)

lemma dmo_bind_valid':
  "\<lbrace>P\<rbrace> a >>= (\<lambda>rv. do_machine_op (b rv >>= c rv)) \<lbrace>Q\<rbrace>
    = \<lbrace>P\<rbrace> a >>= (\<lambda>rv. do_machine_op (b rv) >>= (\<lambda>rv'. do_machine_op (c rv rv'))) \<lbrace>Q\<rbrace>"
  by (fastforce simp: do_machine_op_def gets_def get_def select_f_def modify_def put_def return_def bind_def valid_def)

lemma dmo_mapM_wp:
  assumes x: "\<And>x. x \<in> S \<Longrightarrow> \<lbrace>P\<rbrace> do_machine_op (f x) \<lbrace>\<lambda>rv. P\<rbrace>"
  shows      "set xs \<subseteq> S \<Longrightarrow> \<lbrace>P\<rbrace> do_machine_op (mapM f xs) \<lbrace>\<lambda>rv. P\<rbrace>"
  apply (induct xs)
   apply (simp add: mapM_def sequence_def)
  apply (simp add: mapM_Cons)
  apply (simp add: dmo_bind_valid dmo_bind_valid')
  apply wp
   apply assumption
  apply (simp add: x)
  done

lemma dmo_mapM_x_wp:
  assumes x: "\<And>x. x \<in> S \<Longrightarrow> \<lbrace>P\<rbrace> do_machine_op (f x) \<lbrace>\<lambda>rv. P\<rbrace>"
  shows      "set xs \<subseteq> S \<Longrightarrow> \<lbrace>P\<rbrace> do_machine_op (mapM_x f xs) \<lbrace>\<lambda>rv. P\<rbrace>"
  apply (subst mapM_x_mapM)
  apply (simp add: do_machine_op_return_foo)
  apply wp
  apply (rule dmo_mapM_wp)
   apply (rule x)
   apply assumption+
  done

lemmas dmo_mapM_x_wp_inv = dmo_mapM_x_wp[where S=UNIV, simplified]

lemma dmo_cacheRangeOp_lift:
  "(\<And>a b. \<lbrace>P\<rbrace> do_machine_op (oper a b) \<lbrace>\<lambda>_. P\<rbrace>)
    \<Longrightarrow> \<lbrace>P\<rbrace> do_machine_op (cacheRangeOp oper x y z) \<lbrace>\<lambda>_. P\<rbrace>"
  apply (simp add: cacheRangeOp_def)
  apply (wp dmo_mapM_x_wp_inv)
  apply (simp add: split_def)
  done

lemma dmo_cleanCacheRange_PoU_respects [wp]:
  "\<lbrace>integrity aag X st\<rbrace> do_machine_op (cleanCacheRange_PoU vstart vend pstart) \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  by (simp add: cleanCacheRange_PoU_def cleanByVA_PoU_def | wp dmo_cacheRangeOp_lift dmo_mol_respects)+

lemma dmo_mapM_x_cleanCacheRange_PoU_integrity:
     "\<lbrace>integrity aag X st\<rbrace>
      do_machine_op
           (mapM_x (\<lambda>x. cleanCacheRange_PoU (f x) (g x) (h x)) refs)
       \<lbrace>\<lambda>_. integrity aag X st\<rbrace>"
  by (wp dmo_mapM_x_wp_inv)

definition word_object_size :: "apiobject_type \<Rightarrow> nat" where
  "word_object_size aobject_type \<equiv>
    (case aobject_type of
         (ArchObject SmallPageObj) \<Rightarrow> 12 |
         (ArchObject LargePageObj) \<Rightarrow> 16 |
         (ArchObject SectionObj) \<Rightarrow> 20 |
         (ArchObject SuperSectionObj) \<Rightarrow> 24)"

definition word_object_range_cover_auth :: "'a PAS \<Rightarrow> apiobject_type \<Rightarrow> word32 \<Rightarrow> nat \<Rightarrow> nat \<Rightarrow> bool" where
  "word_object_range_cover_auth aag new_type ptr sz num_objects \<equiv>
    if new_type \<in> ArchObject ` {SmallPageObj,LargePageObj,SectionObj,SuperSectionObj} then range_cover ptr sz (word_object_size new_type) num_objects \<and>
    (\<forall>y\<in>{ptr..ptr + (of_nat num_objects)*(2^(word_object_size new_type)) - 1}. is_subject aag y)
    else True"

lemma init_arch_objects_integrity:
  "\<lbrace>integrity aag X st and
    K (\<forall> x\<in>set refs. is_subject aag x) and
    K (\<forall> x\<in>set refs. new_type = ArchObject PageDirectoryObj \<longrightarrow> is_aligned x pd_bits) and
    K (word_object_range_cover_auth aag new_type ptr sz num_objects \<and>
       of_nat num_objects > (0::word32))\<rbrace>
     init_arch_objects new_type ptr num_objects obj_sz refs
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply(rule hoare_gen_asm)+
  apply(cases new_type)
  apply(simp_all add: init_arch_objects_def)
  apply(rule hoare_pre)
   apply(wpc
        | wp create_word_objects_integrity mapM_x_wp[OF _ subset_refl]
             copy_global_mappings_integrity dmo_mapM_x_cleanCacheRange_PoU_integrity
        | simp add: obj_bits_api_def default_arch_object_def)+
  apply(auto simp: word_object_range_cover_auth_def word_object_size_def split: apiobject_type.splits aobject_type.splits split_if_asm)
  done

lemma foldr_upd_app_if': "foldr (\<lambda>p ps. ps(p := f p)) as g = (\<lambda>x. if x \<in> set as then (f x) else g x)"
  apply (induct as)
   apply simp
  apply simp
  apply (rule ext)
  apply simp
  done


lemma retype_region_integrity:
  "\<lbrace>integrity aag X st and
    K (range_cover ptr sz (obj_bits_api type o_bits) num_objects \<and>
       (\<forall>x\<in>{ptr..(ptr && ~~ mask sz) + (2 ^ sz - 1)}. is_subject aag x))\<rbrace>
   retype_region ptr num_objects o_bits type
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply(rule hoare_gen_asm)+
  apply(simp only: retype_region_def retype_region_ext_extended.dxo_eq)
  apply(simp only: retype_addrs_def  retype_region_ext_def
                   foldr_upd_app_if' fun_app_def K_bind_def)
  apply(wp)
  apply (clarsimp simp: not_less)
  apply (erule integrity_trans)
  apply (clarsimp simp add: integrity_def)
  apply(fastforce intro: tro_lrefl tre_lrefl
                 dest: retype_addrs_subset_ptr_bits[simplified retype_addrs_def]
                 simp: set_map image_def p_assoc_help power_sub integrity_def)
 done

lemma retype_region_ret_is_subject:
  "\<lbrace>K (range_cover ptr sz (obj_bits_api tp us) num_objects \<and>
       (\<forall>x\<in>{ptr..(ptr && ~~ mask sz) + (2 ^ sz - 1)}. is_subject aag x))\<rbrace>
   retype_region ptr num_objects us tp
   \<lbrace>\<lambda>rv. K (\<forall> ref \<in> set rv. is_subject aag ref)\<rbrace>"
  apply(rule hoare_gen_asm2 | rule hoare_gen_asm)+
  apply(rule hoare_strengthen_post)
  apply(rule retype_region_ret)
  apply(simp only: K_def)
  apply(rule ballI)
  apply(elim conjE)
  apply(erule bspec)
  apply(rule rev_subsetD, assumption)
  apply(simp add: p_assoc_help del: set_map)
  apply(rule retype_addrs_subset_ptr_bits[simplified retype_addrs_def])
   apply simp+
  done

lemma retype_region_ret_pd_aligned:
  "\<lbrace>K (range_cover ptr sz (obj_bits_api tp us) num_objects)\<rbrace>
   retype_region ptr num_objects us tp
   \<lbrace>\<lambda>rv. K (\<forall> ref \<in> set rv. tp = ArchObject PageDirectoryObj \<longrightarrow> is_aligned ref pd_bits)\<rbrace>"
  apply(rule hoare_strengthen_post)
  apply(rule hoare_weaken_pre)
  apply(rule retype_region_aligned_for_init)
   apply simp
  apply (clarsimp simp: obj_bits_api_def default_arch_object_def pd_bits_def pageBits_def)
  done

declare wrap_ext_det_ext_ext_def[simp]

lemma detype_integrity:
  "\<lbrakk>integrity aag X st s; (\<forall> r\<in>refs. is_subject aag r)\<rbrakk> \<Longrightarrow>
    integrity aag X st (detype refs s)"
  apply (erule integrity_trans)
  apply (auto simp: detype_def detype_ext_def integrity_def)
  done

lemma state_vrefs_detype [simp]:
  "state_vrefs (detype R s) = (\<lambda>x. if x \<in> R then {} else state_vrefs s x)"
  unfolding state_vrefs_def
  apply (rule ext)
  apply (clarsimp simp: detype_def)
  done

lemma global_refs_detype [simp]:
  "global_refs (detype R s) = global_refs s"
  by(simp add: detype_def)

lemma thread_states_detype[simp]:
  "thread_states (detype S s) = (\<lambda>x. if x \<in> S then {} else thread_states s x)"
  by (rule ext, simp add: thread_states_def get_tcb_def  o_def detype_def tcb_states_of_state_def)

lemma thread_bound_ntfns_detype[simp]:
  "thread_bound_ntfns (detype S s) = (\<lambda>x. if x \<in> S then None else thread_bound_ntfns s x)"
  by (rule ext, simp add: thread_bound_ntfns_def get_tcb_def  o_def detype_def tcb_states_of_state_def)

lemma sta_detype:
  "state_objs_to_policy (detype R s) \<subseteq> state_objs_to_policy s"
  apply (clarsimp simp add: state_objs_to_policy_def state_refs_of_detype)
  apply (erule state_bits_to_policy.induct)
  apply (auto intro: state_bits_to_policy.intros split: split_if_asm)
  done

lemma sita_detype:
  "state_irqs_to_policy aag (detype R s) \<subseteq> state_irqs_to_policy aag s"
  apply (clarsimp)
  apply (erule state_irqs_to_policy_aux.induct)
  apply (auto simp: detype_def  intro: state_irqs_to_policy_aux.intros split: split_if_asm)
  done

lemma sata_detype:
  "state_asids_to_policy aag (detype R s) \<subseteq> state_asids_to_policy aag s"
  apply (clarsimp)
  apply (erule state_asids_to_policy_aux.induct)
  apply (auto intro: state_asids_to_policy_aux.intros split: split_if_asm)
  done

(* FIXME: move *)
lemmas pas_refined_by_subsets = pas_refined_state_objs_to_policy_subset


lemma detype_irqs [simp]:
  "interrupt_irq_node (detype R s) = interrupt_irq_node s"
  unfolding detype_def by simp

lemma dtsa_detype: "domains_of_state (detype R s) \<subseteq> domains_of_state s"
by (auto simp: detype_def detype_ext_def
        intro: domtcbs
        elim!: domains_of_state_aux.cases
        split: if_splits)

lemma pas_refined_detype:
  "pas_refined aag s \<Longrightarrow> pas_refined aag (detype R s)"
  apply (rule pas_refined_by_subsets)
  apply (blast intro!: sta_detype sata_detype sita_detype detype_irqs dtsa_detype)+
  done

(* TODO: proof has mainly been copied from dmo_clearMemory_respects *)
lemma dmo_freeMemory_respects:
  "\<lbrace>integrity aag X st and
     K (is_aligned ptr bits \<and> bits < word_bits \<and> 2 \<le> bits \<and>
          (\<forall>p \<in> ptr_range ptr bits. is_subject aag p))\<rbrace>
   do_machine_op (freeMemory ptr bits) \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  unfolding do_machine_op_def freeMemory_def
  apply (simp add: split_def)
  apply wp
  apply clarsimp
  apply (erule use_valid)
  apply (wp mol_respects mapM_x_wp' storeWord_integrity_autarch)
  apply simp
  apply (clarsimp simp add: word_size_def upto_enum_step_shift_red [where us = 2, simplified])
  apply (erule bspec)
  apply (erule set_mp [rotated])
  apply (rule ptr_range_subset)
           apply simp
          apply (simp add: is_aligned_mult_triv2 [where n = 2, simplified])
         apply assumption
        apply (erule word_less_power_trans_ofnat [where k = 2, simplified])
       apply assumption
      apply (fold word_bits_def, assumption)
     apply simp
    done

lemma delete_objects_respects[wp]:
  "\<lbrace>integrity aag X st and
    K (is_aligned ptr bits \<and> bits < word_bits \<and>
       2 \<le> bits \<and> (\<forall>p\<in>ptr_range ptr bits. is_subject aag p))\<rbrace>
   delete_objects ptr bits
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
   apply (simp add: delete_objects_def)
   apply (rule_tac seq_ext)
   apply (rule hoare_triv[of P _ "%_. P" for P])
   apply (wp dmo_freeMemory_respects | simp)+
   apply (clarsimp simp: ptr_range_def intro!: detype_integrity)
   done


lemma word_object_range_cover:
  "\<lbrakk>range_cover word2 sz (obj_bits_api apiobject_type o_bits) n; n \<noteq> 0;
    \<forall>x\<in>{word2..(word2 && ~~ mask sz) + 2 ^ sz - 1}. is_subject aag x\<rbrakk> \<Longrightarrow>
   word_object_range_cover_auth aag apiobject_type word2 sz n"
  apply(auto simp: word_object_range_cover_auth_def obj_bits_api_def word_object_size_def default_arch_object_def | auto dest!: range_cover_subset' subsetD)+
  done

lemma invoke_untyped_integrity:
  "\<lbrace>integrity aag X st and valid_objs and authorised_untyped_inv_state aag ui and valid_untyped_inv ui and K (authorised_untyped_inv aag ui)\<rbrace>
     invoke_untyped ui
   \<lbrace>\<lambda>rv. integrity aag X st\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (cases ui)
  apply (rename_tac cslot_ptr word1 word2 apiobject_type nat list)
  apply (simp add: mapM_x_def[symmetric] authorised_untyped_inv_def)
  apply (wp mapM_x_wp[OF _ subset_refl] create_cap_integrity
            init_arch_objects_integrity retype_region_integrity
            retype_region_ret_is_subject retype_region_ret_pd_aligned
            set_cap_integrity_autarch hoare_vcg_if_lift get_cap_wp
    | clarsimp simp: split_paired_Ball
    | erule in_set_zipE | blast)+
  apply(frule (1) cte_wp_at_eqD2)
  apply(clarsimp simp: authorised_untyped_inv_state_def is_aligned_neg_mask_eq ptr_range_def p_assoc_help bits_of_def)
  apply(rule conjI)
   apply(rule impI)
   apply(drule_tac t=word2 in sym)
   apply clarsimp
   apply(drule (1) cte_wp_at_valid_objs_valid_cap)
   apply(clarsimp simp: valid_cap_def cap_aligned_def)
   apply(subgoal_tac "range_cover word2 (bits_of (UntypedCap word2 sz idx)) (obj_bits_api apiobject_type nat) (length list)")
    apply(rule conjI, assumption)
    apply(rule conjI)
     apply(fastforce split: cap.splits simp: bits_of_def)
    apply(rule conjI, assumption)
    apply(rule conjI, fastforce split: cap.splits simp: bits_of_def)
    apply(rule conjI, assumption)
    apply(rule word_object_range_cover)
      apply assumption
     apply(blast dest: unat_less_helper)
    apply(clarsimp simp: bits_of_def split: cap.splits)
    apply(drule_tac x="UntypedCap word2 sz idx" in spec, clarsimp, fastforce simp: p_assoc_help)
   apply(simp add: bits_of_def split: cap.splits)
  apply(rule impI)
  apply(clarsimp simp: bits_of_def split: cap.splits)
  apply(drule_tac x="UntypedCap (word2 && ~~ mask sz) sz idx" in spec, clarsimp)
  apply(rule conjI)
   apply(rule ballI, erule bspec, erule subsetD[rotated], rule range_subsetI[OF word_and_le2], simp+)
  apply(rule word_object_range_cover)
    apply assumption
   apply simp
  apply(rule ballI, erule bspec, erule subsetD[rotated], rule range_subsetI[OF word_and_le2], (simp add: p_assoc_help)+)
  done


lemma clas_default_cap:
  "tp \<noteq> ArchObject ASIDPoolObj \<Longrightarrow> cap_links_asid_slot aag p (default_cap tp p' sz)"
  unfolding cap_links_asid_slot_def
  apply (cases tp, simp_all)
  apply (rename_tac aobject_type) 
  apply (case_tac aobject_type, simp_all add: arch_default_cap_def)
  done

lemma cli_default_cap:
  "tp \<noteq> ArchObject ASIDPoolObj \<Longrightarrow> cap_links_irq aag p (default_cap tp p' sz)"
  unfolding cap_links_irq_def
  apply (cases tp, simp_all)
  done

lemma obj_refs_default_nut:
  "\<lbrakk> tp \<noteq> Untyped; \<forall>atp. tp \<noteq> ArchObject atp \<rbrakk> \<Longrightarrow>
  obj_refs (default_cap tp oref sz) = {oref}"
  by (cases tp, simp_all add: arch_default_cap_def  split: aobject_type.splits)

lemma obj_refs_default':
  "is_aligned oref (obj_bits_api tp sz) \<Longrightarrow> obj_refs (default_cap tp oref sz) \<subseteq> ptr_range oref (obj_bits_api tp sz)"
  by (cases tp, simp_all add: arch_default_cap_def ptr_range_memI obj_bits_api_def default_arch_object_def split: aobject_type.splits)

lemma create_cap_pas_refined:
  "\<lbrace>pas_refined aag and K (tp \<noteq> ArchObject ASIDPoolObj \<and> is_subject aag (fst p) \<and> is_subject aag (fst (fst ref)) \<and>
    (\<forall>x \<in> ptr_range (snd ref) (obj_bits_api tp sz). is_subject aag x)
    \<and> is_aligned (snd ref)  (obj_bits_api tp sz))\<rbrace>
     create_cap tp sz p ref
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply(simp add: create_cap_def split_def)
  apply(wp set_cdt_pas_refined | clarsimp)+
  apply (rule conjI)
   apply (cases "fst ref", clarsimp simp: pas_refined_refl)
  apply (cases "tp = Untyped")
   apply (simp add: cap_links_asid_slot_def pas_refined_refl cap_links_irq_def aag_cap_auth_def ptr_range_def obj_bits_api_def)
  apply (clarsimp simp add:  obj_refs_default_nut clas_default_cap pas_refined_refl cli_default_cap aag_cap_auth_def)
  apply(drule obj_refs_default')
  apply(case_tac tp, simp_all)
  apply(auto intro: pas_refined_refl dest!: subsetD)
  done

crunch pas_refined[wp]: do_machine_op "pas_refined aag"
  (wp: crunch_wps simp: crunch_simps)

lemma create_word_objects_pas_refined:
  "\<lbrace>pas_refined aag\<rbrace>
     create_word_objects ptr bits sz
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply(simp add: create_word_objects_def)
  apply(wp)
  done

crunch arm_global_pd: store_pde "\<lambda> s. P (arm_global_pd (arch_state s))"

lemma pd_shifting_dual':
  "is_aligned (pd::word32) pd_bits \<Longrightarrow>
  pd + (vptr >> 20 << 2) && mask pd_bits = vptr >> 20 << 2"
  apply (subst (asm) pd_bits_def)
  apply (subst (asm) pageBits_def)
  apply( simp add: pd_shifting_dual)
  done


lemma empty_table_update_from_arm_global_pts:
  "\<lbrakk>valid_global_objs s;
    kernel_base >> 20 \<le> y >> 20; y >> 20 \<le> 2 ^ (pd_bits - 2) - 1;
    is_aligned pd pd_bits;
    kheap s (arm_global_pd (arch_state s)) = Some (ArchObj (PageDirectory pda));
    obj_at (empty_table (set (arm_global_pts (arch_state s)))) pd s\<rbrakk>
   \<Longrightarrow>
   (\<forall>pdb. ko_at (ArchObj (PageDirectory pdb)) pd s \<longrightarrow>
       empty_table (set (arm_global_pts (arch_state s)))
                   (ArchObj
                     (PageDirectory
                       (pdb(ucast (y >> 20) := pda (ucast (y >> 20)))))))"
  apply(clarsimp simp: empty_table_def obj_at_def)
  apply(clarsimp simp: valid_global_objs_def obj_at_def empty_table_def)
  done


lemma copy_global_mappings_pas_refined:
  "is_aligned pd pd_bits \<Longrightarrow>
   \<lbrace>pas_refined aag and valid_kernel_mappings and
     valid_arch_state and valid_global_objs and valid_global_refs and
     pspace_aligned\<rbrace>
     copy_global_mappings pd
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply(simp add: copy_global_mappings_def)
  apply(rule hoare_weaken_pre)
  apply(wp)
  (* Use \<circ> to avoid wp filtering out the global_pd condition here
     TODO: see if we can clean this up *)
  apply(rule_tac Q="\<lambda> rv s. is_aligned global_pd pd_bits \<and> (global_pd = (arm_global_pd \<circ> arch_state) s \<and> valid_kernel_mappings s \<and> valid_arch_state s \<and> valid_global_objs s \<and> valid_global_refs s \<and> pas_refined aag s)" in hoare_strengthen_post)
  apply(rule mapM_x_wp[OF _ subset_refl])
    apply (rule hoare_seq_ext)
     apply(unfold o_def)
     (* Use [1] so wp doesn't filter out the global_pd condition *)
     apply(wp store_pde_pas_refined store_pde_arm_global_pd
              store_pde_valid_kernel_mappings_map_global)[1]
     apply(frule subsetD[OF copy_global_mappings_index_subset])
     apply(rule hoare_gen_asm[simplified K_def pred_conj_def conj_commute])
     apply(simp add: get_pde_def)
     apply(subst kernel_vsrefs_kernel_mapping_slots[symmetric])
     apply(wp)
     apply(clarsimp simp: get_pde_def pd_shifting' pd_shifting_dual' K_def triple_shift_fun)
     apply(subst (asm) obj_at_def, erule exE, erule conjE)
     apply(rotate_tac -1, drule sym, simp)
     apply(frule (1) valid_kernel_mappingsD[folded obj_at_def])
     apply(clarsimp simp: kernel_mapping_slots_def shiftr_20_less
                          empty_table_update_from_arm_global_pts
                          global_refs_def pde_ref_def)
     apply(fastforce)
    apply fastforce
   apply(rule gets_wp)
  apply(simp, blast intro: invs_aligned_pdD)
  done



lemma copy_global_invs_mappings_restricted':
  "pd \<in> S \<Longrightarrow>
   \<lbrace>all_invs_but_equal_kernel_mappings_restricted S
    and (\<lambda>s. S \<inter> global_refs s = {})
    and K (is_aligned pd pd_bits)\<rbrace>
    copy_global_mappings pd
   \<lbrace>\<lambda>rv. all_invs_but_equal_kernel_mappings_restricted S\<rbrace>"
  apply(rule hoare_weaken_pre)
  apply(rule copy_global_invs_mappings_restricted)
  apply(simp add: insert_absorb)
  done

lemma init_arch_objects_pas_refined:
  "\<lbrace>pas_refined aag and
    post_retype_invs tp refs and
    (\<lambda> s. \<forall> x\<in>set refs. x \<notin> global_refs s) and
    K (\<forall> x\<in>set refs. tp = ArchObject PageDirectoryObj \<longrightarrow> is_aligned x pd_bits)\<rbrace>
     init_arch_objects tp ptr bits obj_sz refs
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply(rule hoare_gen_asm)
  apply(cases tp)
       apply(simp_all add: init_arch_objects_def)
       apply(wp | simp)+
  apply(rename_tac aobject_type)
  apply(case_tac aobject_type, simp_all)
        apply((simp | wp create_word_objects_pas_refined)+)[5]
   apply(wp)
    apply(rule_tac Q="\<lambda> rv. pas_refined aag and all_invs_but_equal_kernel_mappings_restricted (set refs) and (\<lambda> s. \<forall> x\<in>set refs. x \<notin> global_refs s)" in hoare_strengthen_post)
     apply(wp mapM_x_wp[OF _ subset_refl])
     apply((wp copy_global_mappings_pas_refined
               copy_global_invs_mappings_restricted'
               copy_global_mappings_global_refs_inv
               copy_global_invs_mappings_restricted' |
            fastforce)+)[2]
   apply(wp dmo_invs hoare_vcg_const_Ball_lift
            valid_irq_node_typ |
         fastforce simp: post_retype_invs_def)+
  done

end

locale retype_region_proofs' = retype_region_proofs + constrains s ::"det_ext state" and s' :: "det_ext state"

context retype_region_proofs
begin

interpretation Arch . (*FIXME; arch_split*)

lemma vs_refs_no_global_pts_default [simp]:
  "vs_refs_no_global_pts (default_object ty us) = {}"
  by (simp add: default_object_def default_arch_object_def tyunt
                vs_refs_no_global_pts_def pde_ref2_def pte_ref_def
                o_def
           split: Structures_A.apiobject_type.splits aobject_type.splits)

lemma vrefs_eq: "state_vrefs s' = state_vrefs s"
  apply(rule ext)
  apply(simp add: s'_def state_vrefs_def ps_def orthr split: option.split)
  done

lemma ts_eq[simp]: "thread_states s' = thread_states s"
  apply (rule ext)
  apply (simp add: s'_def ps_def thread_states_def get_tcb_def orthr tcb_states_of_state_def
            split: option.split Structures_A.kernel_object.split)
  apply (simp add: default_object_def default_tcb_def tyunt
            split: Structures_A.apiobject_type.split)
  done

lemma bas_eq[simp]: "thread_bound_ntfns s' = thread_bound_ntfns s"
  apply (rule ext)
  apply (simp add: s'_def ps_def thread_bound_ntfns_def get_tcb_def orthr tcb_states_of_state_def
            split: option.split Structures_A.kernel_object.split)
  apply (simp add: default_object_def default_tcb_def tyunt
            split: Structures_A.apiobject_type.split)
  done
end

context retype_region_proofs'
begin

interpretation Arch . (*FIXME; arch_split*)

lemma domains_of_state: "domains_of_state s' \<subseteq> domains_of_state s"
  unfolding s'_def by simp

lemma pas_refined: "pas_refined aag s \<Longrightarrow> pas_refined aag s'"
  apply(erule pas_refined_state_objs_to_policy_subset)
     apply(simp add: state_objs_to_policy_def refs_eq vrefs_eq mdb_and_revokable)
     apply(rule subsetI, rename_tac x, case_tac x, simp)
     apply(erule state_bits_to_policy.cases)
          apply(auto intro!: sbta_caps intro: caps_retype split: cap.split)[1]
         apply(auto intro!: sbta_untyped intro: caps_retype split: cap.split)[1]
        apply((blast intro: state_bits_to_policy.intros)+)[4]
    apply (simp add: vrefs_eq)
    apply(auto elim!: state_asids_to_policy_aux.cases
               intro: state_asids_to_policy_aux.intros caps_retype
               split: cap.split dest: sata_asid[OF caps_retype, rotated])[1]
   apply clarsimp
   apply (erule state_irqs_to_policy_aux.cases)
    apply(auto intro!: sita_controlled intro: caps_retype split: cap.split)[1]
   apply (rule domains_of_state)
  apply simp
  done

end

context begin interpretation Arch . (*FIXME: arch_split*)

lemma retype_region_ext_kheap_update:
  "\<lbrace>Q xs and R xs\<rbrace> retype_region_ext xs ty \<lbrace>\<lambda>_. Q xs\<rbrace>
  \<Longrightarrow> \<lbrace>\<lambda>s. Q xs (kheap_update f s) \<and> R xs (kheap_update f s)\<rbrace> retype_region_ext xs ty \<lbrace>\<lambda>_ s. Q xs (kheap_update f s)\<rbrace>"
  apply (clarsimp simp: valid_def retype_region_ext_def)
  apply (erule_tac x="kheap_update f s" in allE)
  apply (clarsimp simp: split_def bind_def gets_def get_def return_def modify_def put_def)
  done

lemma use_retype_region_proofs_ext':
  assumes x: "\<And>(s::det_ext state). \<lbrakk> retype_region_proofs s ty us ptr sz n; P s \<rbrakk>
   \<Longrightarrow> Q (retype_addrs ptr ty n us) (s\<lparr>kheap :=
           \<lambda>x. if x \<in> set (retype_addrs ptr ty n us)
             then Some (default_object ty us)
             else kheap s x\<rparr>)"
  assumes y: "\<And>xs. \<lbrace>Q xs and R xs\<rbrace> retype_region_ext xs ty \<lbrace>\<lambda>_. Q xs\<rbrace>"
  assumes z: "\<And>f xs s. R xs (kheap_update f s) = R xs s"
  shows
    "\<lbrakk> ty = CapTableObject \<Longrightarrow> 0 < us;
         \<And>s. P s \<Longrightarrow> Q (retype_addrs ptr ty n us) s \<rbrakk> \<Longrightarrow>
    \<lbrace>\<lambda>s. valid_pspace s \<and> valid_mdb s \<and> range_cover ptr sz (obj_bits_api ty us) n 
        \<and> caps_overlap_reserved {ptr..ptr + of_nat n * 2 ^ obj_bits_api ty us - 1} s
        \<and> caps_no_overlap ptr sz s \<and> pspace_no_overlap ptr sz s \<and>
        P s \<and> R (retype_addrs ptr ty n us) s\<rbrace> retype_region ptr n us ty \<lbrace>Q\<rbrace>"
  apply (simp add: retype_region_def split del: split_if)
  apply (rule hoare_pre, (wp|simp)+)
    apply (rule retype_region_ext_kheap_update[OF y])
   apply (wp|simp)+
  apply (clarsimp simp: retype_addrs_fold 
                        foldr_upd_app_if fun_upd_def[symmetric])
  apply safe
  apply (rule x)
   apply (rule retype_region_proofs.intro, simp_all)[1]
   apply (simp add: range_cover_def obj_bits_api_def z
     slot_bits_def word_bits_def cte_level_bits_def)+
   done

lemmas use_retype_region_proofs_ext
    = use_retype_region_proofs_ext'[where Q="\<lambda>_. Q" and P=Q, simplified] for Q

end

lemma (in is_extended) pas_refined_tcb_domain_map_wellformed':
  assumes tdmw: "\<lbrace>tcb_domain_map_wellformed aag and P\<rbrace> f \<lbrace>\<lambda>_. tcb_domain_map_wellformed aag\<rbrace>"
  shows "\<lbrace>pas_refined aag and P\<rbrace> f \<lbrace>\<lambda>_. pas_refined aag\<rbrace>"
apply (simp add: pas_refined_def)
apply (wp tdmw)
apply (wp lift_inv)
apply simp+
done

context begin interpretation Arch . (*FIXME: arch_split*)

lemma retype_region_ext_pas_refined:
  "\<lbrace>pas_refined aag and pas_cur_domain aag and K (\<forall>x\<in> set xs. is_subject aag x)\<rbrace> retype_region_ext xs ty \<lbrace>\<lambda>_. pas_refined aag\<rbrace>"
  apply (subst and_assoc[symmetric])
  apply (wp retype_region_ext_extended.pas_refined_tcb_domain_map_wellformed')
  apply (simp add: retype_region_ext_def, wp)
  apply (clarsimp simp: tcb_domain_map_wellformed_aux_def)
  apply (erule domains_of_state_aux.cases)
  apply (clarsimp simp: foldr_upd_app_if' fun_upd_def[symmetric] split: split_if_asm)
   apply (clarsimp simp: default_ext_def default_etcb_def split: apiobject_type.splits)
   defer
  apply (force intro: domtcbs)
  done

lemma retype_region_pas_refined:
  "\<lbrace>pas_refined aag and pas_cur_domain aag and 
    valid_pspace and valid_mdb and
    caps_overlap_reserved
            {ptr..ptr + of_nat num_objects * 2 ^ obj_bits_api type o_bits -
                  1} and
    caps_no_overlap ptr sz and pspace_no_overlap ptr sz and
    K (range_cover ptr sz (obj_bits_api type o_bits) num_objects) and
    K (\<forall>x\<in>set (retype_addrs ptr type num_objects o_bits). is_subject aag x) and
    K ((type = CapTableObject \<longrightarrow> 0 < o_bits))\<rbrace>
     retype_region ptr num_objects o_bits type
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (rule hoare_pre)
  apply(rule use_retype_region_proofs_ext)
     apply(erule (1) retype_region_proofs'.pas_refined[OF retype_region_proofs'.intro])
    apply (wp retype_region_ext_pas_refined)
    apply simp
   apply auto
   done

(* MOVE *)
lemma retype_region_aag_bits:
  "\<lbrace>\<lambda>s. P (null_filter (caps_of_state s)) (state_refs_of s) (cdt s) (state_vrefs s)
       \<and> valid_pspace s \<and> valid_mdb s \<and>
           caps_overlap_reserved
            {ptr..ptr + of_nat num_objects * 2 ^ obj_bits_api tp us - 1} s \<and>
           caps_no_overlap ptr sz s \<and> pspace_no_overlap ptr sz s
       \<and> ((tp = CapTableObject \<longrightarrow> 0 < us) \<and> range_cover ptr sz (obj_bits_api tp us) num_objects)\<rbrace>
  retype_region ptr num_objects us tp
  \<lbrace>\<lambda>_ s. P (null_filter (caps_of_state s)) (state_refs_of s) (cdt s) (state_vrefs s)\<rbrace>"
  apply (subst conj_assoc [symmetric])+
  apply (rule hoare_gen_asm [unfolded pred_conj_def K_def])+
  apply (rule hoare_pre)
   apply (rule use_retype_region_proofs)
      apply (frule retype_region_proofs.null_filter, erule ssubst)
      apply (frule retype_region_proofs.refs_eq, erule ssubst)
      apply (frule retype_region_proofs.vrefs_eq, erule ssubst)
      apply (frule retype_region_proofs.mdb_and_revokable, erule ssubst)
      apply assumption
     apply simp
    apply simp
   apply simp
  apply blast
  done

lemma retype_region_ranges'':
  "\<lbrace>K (range_cover ptr sz (obj_bits_api tp us) num_objects \<and> num_objects \<noteq> 0)\<rbrace>
  retype_region ptr num_objects us tp
   \<lbrace>\<lambda>rv s. \<forall>y\<in>set rv. ptr_range y (obj_bits_api tp us) \<subseteq> {ptr..ptr + of_nat num_objects * 2 ^ (obj_bits_api tp us) - 1}\<rbrace>"
  apply simp
  apply (rule hoare_gen_asm[where P'="\<top>", simplified])
  apply (rule hoare_strengthen_post [OF retype_region_ret])
  apply (clarsimp)
  apply (frule_tac p=y in range_cover_subset)
    apply assumption
   apply simp
  apply(rule conjI)
   apply (fastforce simp: ptr_range_def ptr_add_def)
  apply(clarsimp simp: ptr_range_def ptr_add_def intro: order_trans)
  apply(erule order_trans)
  apply(erule impE)
   apply(simp add: p_assoc_help)
   apply(rule is_aligned_no_wrap')
    apply(rule is_aligned_add)
     apply(fastforce simp: range_cover_def)
    apply(simp add: is_aligned_mult_triv2)
   apply(rule minus_one_helper, simp)
   apply(rule power_not_zero)
   apply(simp add: range_cover_def)
  apply simp
  done

lemma detype_msu_comm:
  "detype S (machine_state_update f s) = machine_state_update f (detype S s)"
  by (case_tac s, simp add: detype_def ext)


lemma region_in_kernel_window_msu[simp]:
  "region_in_kernel_window S (machine_state_update f s) =
   region_in_kernel_window S s"
  by (simp add: region_in_kernel_window_def)

lemma region_in_kernel_window_preserved:
  assumes "\<And> P. \<lbrace>\<lambda> s. P (arch_state s) \<rbrace> f \<lbrace>\<lambda> rv s. P (arch_state s) \<rbrace>"
  shows "\<And> S. \<lbrace> region_in_kernel_window S \<rbrace> f \<lbrace> \<lambda>_. region_in_kernel_window S \<rbrace>"
  apply(clarsimp simp: valid_def region_in_kernel_window_def)
  apply(erule use_valid)
  apply(rule assms)
  apply simp
  done

lemma pspace_no_overlap_msu[simp]:
  "pspace_no_overlap w n (machine_state_update f s) = pspace_no_overlap w n s"
  apply(clarsimp simp: pspace_no_overlap_def)
  done

lemma descendants_range_in_msu[simp]:
  "descendants_range_in S slot (machine_state_update f s) = descendants_range_in S slot s"
  apply(clarsimp simp: descendants_range_in_def)
  done

(* proof clagged from Retype_AI.clearMemory_vms *)
lemma freeMemory_vms:
  "valid_machine_state s \<Longrightarrow>
   \<forall>x\<in>fst (freeMemory ptr bits (machine_state s)).
   valid_machine_state (s\<lparr>machine_state := snd x\<rparr>)"
  apply (clarsimp simp: valid_machine_state_def
                        disj_commute[of "in_user_frame p s" for p s])
  apply (drule_tac x=p in spec, simp)
  apply (drule_tac P4="\<lambda>m'. underlying_memory m' p = 0"
         in use_valid[where P=P and Q="\<lambda>_. P" for P], simp_all)
  apply (simp add: freeMemory_def machine_op_lift_def
                   machine_rest_lift_def split_def)
  apply (wp hoare_drop_imps | simp | wp mapM_x_wp_inv)+
  apply (simp add: storeWord_def | wp)+
  apply (simp add: word_rsplit_0)
  done


lemma dmo_freeMemory_vms:
  "\<lbrace>valid_machine_state\<rbrace>
     do_machine_op (freeMemory ptr bits)
   \<lbrace>\<lambda>_. valid_machine_state\<rbrace>"
  apply(unfold do_machine_op_def)
  apply (wp modify_wp freeMemory_vms | simp add: split_def)+
  done

lemma freeMemory_valid_irq_states:
  "\<lbrace>\<lambda>m. valid_irq_states (s\<lparr>machine_state := m\<rparr>) \<rbrace>
   freeMemory ptr bits
   \<lbrace>\<lambda>a b. valid_irq_states (s\<lparr>machine_state := b\<rparr>)\<rbrace>"
  unfolding freeMemory_def
  apply(wp mapM_x_wp[OF _ subset_refl] storeWord_valid_irq_states)
  done

lemma dmo_freeMemory_invs:
  "\<lbrace> invs \<rbrace>
     do_machine_op (freeMemory ptr bits)
   \<lbrace>\<lambda>_. invs\<rbrace>"
  apply(simp add: do_machine_op_def invs_def valid_state_def cur_tcb_def | wp | wpc)+
  apply(clarsimp)
  apply(rule conjI)
   apply(erule use_valid[OF _ freeMemory_valid_irq_states], simp)
  apply(drule freeMemory_vms)
  by auto


lemma delete_objects_pas_refined:
  "\<lbrace>pas_refined aag\<rbrace> delete_objects ptr sz \<lbrace>\<lambda>_. pas_refined aag\<rbrace>"
  apply(simp add: delete_objects_def do_machine_op_def)
  apply (wp modify_wp | simp add: split_def)+
  apply clarsimp
  apply(rule pas_refined_detype)
  apply simp
  done


lemma cte_wp_at_sym:
  "cte_wp_at (\<lambda> c. c = cap) slot s = cte_wp_at (op = cap) slot s"
  apply(simp add: cte_wp_at_def)
  done

lemma untyped_slots_not_in_untyped_range:
  "\<lbrakk>invs s; descendants_range_in S slot s; cte_wp_at (op = cap) slot s;
    is_untyped_cap cap; S = untyped_range cap; T \<subseteq> S\<rbrakk> \<Longrightarrow>
   fst slot \<notin> T"
  apply(erule contra_subsetD)
  proof -
  assume i: "invs s" and
         dr: "descendants_range_in S slot s" and
         ct: "cte_wp_at (op = cap) slot s" and
         ut: "is_untyped_cap cap" and
          r: "S = untyped_range cap"
  hence dt: "detype_locale cap slot s"
   by(simp add: detype_locale_def descendants_range_def2 invs_untyped_children)
  show "fst slot \<notin> S"
  apply -
  apply (insert r)
  apply (simp, rule detype_locale.non_null_present[OF dt])
  apply (insert ct ut)
  apply (case_tac cap, simp_all)
  apply (auto simp: cte_wp_at_def)
  done
  qed

lemma descendants_range_in_detype:
  "\<lbrakk>invs s; descendants_range_in S slot s; cte_wp_at (op = cap) slot s;
    is_untyped_cap cap; S = untyped_range cap; T \<subseteq> S\<rbrakk> \<Longrightarrow>
   descendants_range_in T slot (detype S s)"
  apply(erule descendants_range_in_subseteq[rotated])
  proof -
  assume i: "invs s" and
         dr: "descendants_range_in S slot s" and
         ct: "cte_wp_at (op = cap) slot s" and
         ut: "is_untyped_cap cap" and
          r: "S = untyped_range cap"
  hence dt: "detype_locale cap slot s"
   by(simp add: detype_locale_def descendants_range_def2 invs_untyped_children)
  show "descendants_range_in S slot (detype S s)"
  apply -
  apply(insert i dr ct ut r)
  apply(simp add: valid_mdb_descendants_range_in[OF invs_mdb])
  apply(simp add: descendants_range_in_def)
  apply(rule ballI)
  apply(drule_tac x=p' in bspec, assumption)
  apply(clarsimp simp: null_filter_def split: split_if_asm)
  apply(rule conjI)
   apply(simp add: cte_wp_at_caps_of_state)
  apply(rule_tac t=a in ssubst[OF fst_conv[symmetric]])
  apply(rule_tac ptr=slot and s=s in detype_locale.non_null_present)
   apply(rule dt)
  apply(simp add: cte_wp_at_caps_of_state)
  apply fastforce
  done
  qed

lemma descendants_range_in_detype_ex:
  "\<lbrakk>invs s; descendants_range_in S slot s; \<exists> cap. cte_wp_at (op = cap) slot s \<and>
    is_untyped_cap cap \<and> S = untyped_range cap; T \<subseteq> S\<rbrakk> \<Longrightarrow>
   descendants_range_in T slot (detype S s)"
  apply clarsimp
  apply(blast intro: descendants_range_in_detype)
  done

lemma descendants_range_in_detype_ex_strengthen:
  "(invs s \<and> descendants_range_in S slot s \<and> (\<exists> cap. cte_wp_at (op = cap) slot s \<and>
    is_untyped_cap cap \<and> S = untyped_range cap) \<and> T \<subseteq> S) \<longrightarrow>
   descendants_range_in T slot (detype S s)"
  apply(blast intro: descendants_range_in_detype_ex)
  done

lemma delete_objects_descendants_range_in':
  notes modify_wp[wp del]
  shows
    "\<lbrace>invs and (\<lambda> s. \<exists> idx. cte_wp_at (op = (UntypedCap word2 sz idx)) slot s) and
     descendants_range_in {word2..word2 + 2 ^ sz - 1} slot\<rbrace>
     (delete_objects word2 sz)
     \<lbrace>\<lambda>_. descendants_range_in {word2..word2 + 2 ^ sz - 1} slot\<rbrace>"
  apply(rule hoare_pre)
   unfolding delete_objects_def
   apply (wp modify_wp dmo_freeMemory_invs
         | strengthen descendants_range_in_detype_ex_strengthen)+
   apply (wp descendants_range_in_lift hoare_vcg_ex_lift | elim conjE | simp)+
  apply clarsimp
  apply(fastforce)
  done

lemma untyped_cap_aligned:
  "\<lbrakk>cte_wp_at (op = (UntypedCap word sz idx)) slot s; valid_objs s\<rbrakk> \<Longrightarrow>
   is_aligned word sz"
  apply(fastforce dest: cte_wp_at_valid_objs_valid_cap simp: valid_cap_def cap_aligned_def)
  done

lemma delete_objects_descendants_range_in'':
  shows
    "\<lbrace>invs and (\<lambda> s. \<exists> idx. cte_wp_at (op = (UntypedCap word2 sz idx)) slot s) and
     descendants_range_in {word2..word2 + 2 ^ sz - 1} slot\<rbrace>
     (delete_objects word2 sz)
     \<lbrace>\<lambda>_. descendants_range_in {word2..(word2 && ~~ mask sz) + 2 ^ sz - 1} slot\<rbrace>"
  apply(clarsimp simp: valid_def)
  apply(frule untyped_cap_aligned, fastforce)
  apply(clarsimp simp: is_aligned_neg_mask_eq)
  apply(erule use_valid)
   apply(wp delete_objects_descendants_range_in' | clarsimp | blast)+
  done

lemma delete_objects_descendants_range_in''':
  shows
    "\<lbrace>invs and (\<lambda> s. \<exists> idx. cte_wp_at (op = (UntypedCap word2 sz idx)) slot s) and
     descendants_range_in {word2..word2 + 2 ^ sz - 1} slot\<rbrace>
     (delete_objects word2 sz)
     \<lbrace>\<lambda>_. descendants_range_in {word2 && ~~ mask sz..(word2 && ~~ mask sz) + 2 ^ sz - 1} slot\<rbrace>"
  apply(clarsimp simp: valid_def)
  apply(frule untyped_cap_aligned, fastforce)
  apply(clarsimp simp: is_aligned_neg_mask_eq)
  apply(erule use_valid)
   apply(wp delete_objects_descendants_range_in' | clarsimp | blast)+
  done


lemma delete_objects_descendants_range_in'''':
  shows
   "\<lbrace>invs and (\<lambda> s. \<exists> idx. cte_wp_at (op = (UntypedCap word2 sz idx)) slot s) and
    ct_active and descendants_range_in {word2..word2 + 2 ^ sz - 1} slot and
     K (range_cover word2 sz bits n \<and>
        n \<noteq> 0)\<rbrace>
          (delete_objects word2 sz)
    \<lbrace>\<lambda>_. descendants_range_in {word2..word2 + of_nat n * 2 ^ bits - 1} slot\<rbrace>"
  apply(clarsimp simp: valid_def)
  apply(rule descendants_range_in_subseteq)
  apply(erule use_valid)
   apply(wp delete_objects_descendants_range_in' | clarsimp | blast)+
  apply(drule range_cover_subset', simp)
  apply(fastforce dest: untyped_cap_aligned simp: is_aligned_neg_mask_eq)
  done

lemmas delete_objects_descendants_range_in =
   delete_objects_descendants_range_in'
   delete_objects_descendants_range_in''
   delete_objects_descendants_range_in'''
   delete_objects_descendants_range_in''''

crunch global_refs[wp]: delete_objects "\<lambda> s. P (global_refs s)"
  (ignore: do_machine_op freeMemory)

crunch arch_state[wp]: delete_objects "\<lambda> s. P (arch_state s)"
  (ignore: do_machine_op freeMemory)



lemma  bits_of_UntypedCap:
  "bits_of (UntypedCap ptr sz free) = sz"
  apply(simp add: bits_of_def split: cap.splits)
  done


lemma mask_neg_mask_is_zero:
  "((x::word32) && ~~ a) && a = 0"
  apply(subst word_bw_assocs)
  apply simp
  done

declare word_neq_0_conv[simp del]

(* clagged from Untyped_R.invoke_untyped_proofs.usable_range_disjoint *)
lemma usable_range_disjoint:
  assumes cte_wp_at: "cte_wp_at (op = (cap.UntypedCap (ptr && ~~ mask sz) sz idx)) cref s"
  assumes  misc     : "distinct slots" "idx \<le> unat (ptr && mask sz) \<or> ptr = ptr && ~~ mask sz"
  "invs s" "slots \<noteq> []" "ct_active s"
  "\<forall>slot\<in>set slots. cte_wp_at (op = cap.NullCap) slot s"
  "\<forall>x\<in>set slots. ex_cte_cap_wp_to (\<lambda>_. True) x s"
  assumes cover: "range_cover ptr sz (obj_bits_api tp us) (length slots)"
  notes blah[simp del] = untyped_range.simps usable_untyped_range.simps atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
          Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex
  shows
       "usable_untyped_range (cap.UntypedCap (ptr && ~~ mask sz) sz
       (unat ((ptr && mask sz) + of_nat (length slots) * 2 ^ obj_bits_api tp us))) \<inter>
       {ptr..ptr + of_nat (length slots) * 2 ^ obj_bits_api tp us - 1} = {}"
      proof -
      have not_0_ptr[simp]: "ptr\<noteq> 0"
      using misc cte_wp_at
      apply (clarsimp simp:cte_wp_at_caps_of_state)
      apply (drule(1) caps_of_state_valid)
      apply (clarsimp simp:valid_cap_def)
      done

      have idx_compare''[simp]:
       "unat ((ptr && mask sz) + (of_nat (length slots) * (2::word32) ^ obj_bits_api tp us)) < 2 ^ sz
        \<Longrightarrow> ptr + of_nat (length slots) * 2 ^ obj_bits_api tp us - 1
        < ptr + of_nat (length slots) * 2 ^ obj_bits_api tp us"
      apply (rule minus_one_helper,simp)
      apply (rule neq_0_no_wrap)
      apply (rule word32_plus_mono_right_split)
      apply (simp add:shiftl_t2n range_cover_unat[OF cover] field_simps)
      apply (simp add:range_cover.sz[where 'a=32, folded word_bits_def, OF cover])+
      done
      show ?thesis
       apply (clarsimp simp:mask_out_sub_mask blah)
       apply (drule idx_compare'')
       apply (simp add:not_le[symmetric])
       done
     qed

lemma set_free_index_invs':
  "\<lbrace> (\<lambda>s. invs s \<and>
         cte_wp_at (op = cap) slot s \<and>
         (free_index_of cap \<le> idx' \<or>
          (descendants_range_in {word1..word1 + 2 ^ (bits_of cap) - 1} slot s \<and>
           pspace_no_overlap word1 (bits_of cap) s)) \<and>
         idx' \<le> 2 ^ cap_bits cap \<and>
         is_untyped_cap cap) and K(word1 = obj_ref_of cap)\<rbrace>
       set_cap
           (UntypedCap word1 (bits_of cap) idx')
            slot
       \<lbrace>\<lambda>_. invs \<rbrace>"
  apply(rule hoare_gen_asm)
  apply(case_tac cap, simp_all add: bits_of_def)
  apply(case_tac "free_index_of cap \<le> idx'")
   apply simp
    apply(cut_tac cap=cap and cref=slot and idx="idx'" in set_free_index_invs)
    apply(simp add: free_index_update_def conj_comms)
   apply simp
   apply(wp set_untyped_cap_invs_simple | simp)+
   apply(fastforce simp: cte_wp_at_def)
   done

lemma delete_objects_pspace_no_overlap:
  "\<lbrace> pspace_aligned and valid_objs and
     cte_wp_at (op = (UntypedCap ptr sz idx)) slot\<rbrace>
    delete_objects ptr sz
   \<lbrace>\<lambda>rv. pspace_no_overlap ptr sz\<rbrace>"
  unfolding delete_objects_def do_machine_op_def
  apply(wp | simp add: split_def detype_msu_comm)+
  apply clarsimp
  apply(rule pspace_no_overlap_detype)
   apply(auto dest: cte_wp_at_valid_objs_valid_cap)
  done

lemma delete_objects_pspace_no_overlap':
  "\<lbrace> pspace_aligned and valid_objs and
     cte_wp_at (op = (UntypedCap ptr sz idx)) slot\<rbrace>
    delete_objects ptr sz
   \<lbrace>\<lambda>rv. pspace_no_overlap (ptr && ~~ mask sz) sz\<rbrace>"
  apply(clarsimp simp: valid_def)
  apply(frule untyped_cap_aligned, simp)
  apply(clarsimp simp: is_aligned_neg_mask_eq)
  apply(erule use_valid, wp delete_objects_pspace_no_overlap, simp)
  done

lemma retype_region_pas_refined':
  "\<lbrace>pas_refined aag and pas_cur_domain aag and invs and
    caps_overlap_reserved
            {ptr..ptr + of_nat num_objects * 2 ^ obj_bits_api type o_bits -
                  1} and
    (\<lambda> s. \<exists> idx. cte_wp_at (\<lambda> c. c = (UntypedCap (ptr && ~~ mask sz) sz idx)) slot s \<and>
                 (idx \<le> unat (ptr && mask sz) \<or>
                  (descendants_range_in {ptr..(ptr && ~~ mask sz) + 2 ^ sz - 1} slot s) \<and>
                    pspace_no_overlap ptr sz s)) and
    K (sz < word_bits) and
    K (range_cover ptr sz (obj_bits_api type o_bits) num_objects) and
    K (\<forall>x\<in>set (retype_addrs ptr type num_objects o_bits). is_subject aag x) and
    K ((type = CapTableObject \<longrightarrow> 0 < o_bits))\<rbrace>
     retype_region ptr num_objects o_bits type
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply(rule hoare_gen_asm)+
  apply(rule hoare_weaken_pre)
  apply(rule use_retype_region_proofs_ext)
     apply(erule (1) retype_region_proofs'.pas_refined[OF retype_region_proofs'.intro])
    apply (wp retype_region_ext_pas_refined)
    apply simp
   apply (auto intro: cte_wp_at_caps_no_overlapI descendants_range_caps_no_overlapI cte_wp_at_pspace_no_overlapI simp: cte_wp_at_sym)
  done


lemma free_index_of_UntypedCap:
  "free_index_of (UntypedCap ptr sz idx) = idx"
  apply(simp add: free_index_of_def)
  done

fun slot_of_untyped_inv where "slot_of_untyped_inv (Retype slot _ _ _ _ _ ) = slot"

lemma region_in_kernel_window_subseteq:
  "\<lbrakk> region_in_kernel_window S s; T \<subseteq> S\<rbrakk> \<Longrightarrow>
     region_in_kernel_window T s"
  apply(fastforce simp: region_in_kernel_window_def)
  done

lemma aag_cap_auth_UntypedCap_idx:
   "aag_cap_auth aag l (UntypedCap base sz idx) \<Longrightarrow>
    aag_cap_auth aag l (UntypedCap base sz idx')"
  apply(clarsimp simp: aag_cap_auth_def cap_links_asid_slot_def cap_links_irq_def)
  done

lemma cte_wp_at_pas_cap_cur_auth_UntypedCap_idx:
  "\<lbrakk>cte_wp_at (op = (UntypedCap base sz idx)) slot s; is_subject aag (fst slot);
    pas_refined aag s\<rbrakk> \<Longrightarrow>
  pas_cap_cur_auth aag (UntypedCap base sz idx')"
  apply(rule aag_cap_auth_UntypedCap_idx)
  apply(auto intro: cap_cur_auth_caps_of_state simp: cte_wp_at_caps_of_state)
  done


lemma invoke_untyped_pas_refined:
  notes modify_wp[wp del]
  notes usable_untyped_range.simps[simp del]
  shows
  "\<lbrace>pas_refined aag and pas_cur_domain aag and invs and valid_untyped_inv ui and ct_active and authorised_untyped_inv_state aag ui and K (authorised_untyped_inv aag ui)\<rbrace>
     invoke_untyped ui
   \<lbrace>\<lambda>rv. pas_refined aag\<rbrace>"
  apply(rule hoare_gen_asm)
  apply(cases ui)
  apply (rename_tac cslot_ptr word1 word2 apiobject_type nat list)
  apply(simp add: mapM_x_def[symmetric] authorised_untyped_inv_def)
  apply(rule hoare_weaken_pre)
   apply(wp mapM_x_and_const_wp [OF create_cap_pas_refined]
            init_arch_objects_pas_refined retype_region_pas_refined'[where slot="slot_of_untyped_inv ui"]
     | simp)+
       (* strengthen postcondition to talk about retvalue of retype_region *)
   apply (simp add: ball_conj_distrib)
    apply(rule_tac
     Q="\<lambda>rv. (\<lambda>s. global_refs s \<inter> set rv = {}) and
             (\<lambda> s. post_retype_invs apiobject_type rv s) and
             (\<lambda>s. \<forall>p \<in> set rv. is_aligned p (obj_bits_api apiobject_type nat)) and
             K (\<forall>p \<in> set rv. is_subject aag p) and
             K (\<forall>ref\<in>set rv. apiobject_type = ArchObject PageDirectoryObj \<longrightarrow>
                                                     is_aligned ref pd_bits) and
             (\<lambda>s. (\<forall>y\<in>set rv. ptr_range y (obj_bits_api apiobject_type nat) \<subseteq>
                               {word2..word2 + of_nat (length list) * 2 ^ (obj_bits_api apiobject_type nat) - 1}))" in hoare_strengthen_post)
     apply (wp retype_region_ret_is_subject
               retype_region_ranges''
               retype_region_post_retype_invs
               retype_region_aligned_for_init
               retype_region_global_refs_disjoint
               retype_region_ret_pd_aligned)
      apply(fastforce elim!: in_set_zipE)
    (* sanitise postcondition *)
     apply(rule_tac
     Q="\<lambda> rv. pas_refined aag and pas_cur_domain aag and invs and
               caps_overlap_reserved
                {word2..word2 +
                        of_nat (length list) *
                        2 ^ obj_bits_api apiobject_type nat -
                        1} and
               (\<lambda>s. \<exists>idx. cte_wp_at
                           (\<lambda>c. c =
                                UntypedCap
                                 (word2 &&
                                  ~~ mask
                                      (bits_of cap)) (bits_of cap)
                                 idx)
                           (slot_of_untyped_inv ui) s \<and>
                          (idx
                           \<le> unat
                              (word2 &&
                               mask
                                (bits_of cap)) \<or>
                            (descendants_range_in
                             {word2..(word2 && ~~ mask (bits_of cap)) +
                                     2 ^
                                     (bits_of cap) -
                                     1}
                             (slot_of_untyped_inv ui) s \<and>
                           pspace_no_overlap word2
                            (bits_of cap)
                            s))) and
               K (bits_of cap < word_bits) and
               K (range_cover word2
                   (bits_of cap)
                   (obj_bits_api apiobject_type nat) (length list)) and
               K (\<forall>x\<in>set (retype_addrs word2 apiobject_type (length list) nat).
                    is_subject aag x) and
               K (apiobject_type = CapTableObject \<longrightarrow> 0 < nat) and
               (\<lambda>s. {word2..(word2 &&
                             ~~ mask
                                 (bits_of cap)) +
                            2 ^
                            (bits_of cap) -
                            1} \<inter>
                    global_refs s =
                    {}) and
                region_in_kernel_window
                {word2..(word2 &&
                         ~~ mask
                             (bits_of cap)) +
                        2 ^
                        (bits_of cap) -
                        1} and
              K(\<forall>x\<in>{word2..(word2 &&
                              ~~ mask
                                  (bits_of cap)) +
                             (2 ^
                              (bits_of cap) -
                              1)}.
                     is_subject aag x)
     " in hoare_strengthen_post)
     apply (simp)
     apply (wp set_untyped_cap_caps_overlap_reserved
              set_free_index_invs' region_in_kernel_window_preserved
              delete_objects_pas_refined  hoare_ex_wp set_cap_cte_wp_at
              set_cap_no_overlap set_cap_descendants_range_in hoare_vcg_disj_lift
          | simp split del: split_if)+
     apply clarsimp
     apply (intro conjI exI, assumption)
                   apply (auto simp: cte_wp_at_def retype_addrs_def intro:
                       cte_wp_at_caps_no_overlapI
                       descendants_range_caps_no_overlapI
                       cte_wp_at_pspace_no_overlapI dest: unat_less_helper)[15]
    apply(clarsimp split del: split_if)
    apply(simp add: conj_comms cong: conj_cong split del: split_if)
    apply(wp delete_objects_invs delete_objects_pas_refined[where aag=aag]
             delete_objects_descendants_range_in
             region_in_kernel_window_preserved hoare_ex_wp get_cap_wp
             hoare_vcg_disj_lift delete_objects_pspace_no_overlap
             delete_objects_pspace_no_overlap'
          | simp split del: split_if)+
  apply (clarsimp split del: split_if
                  simp: conj_comms cong: conj_cong)
  apply (drule (1) cte_wp_at_eqD2)
  apply (clarsimp split del: split_if
                  simp: conj_comms cong: conj_cong if_cong simp: bits_of_UntypedCap)
  apply(split split_if)
  apply(subgoal_tac "sz < word_bits")
   apply(intro conjI impI)
   apply(simp_all add: cte_wp_at_cte_at cte_wp_at_sym)
                           apply fastforce
                          apply(drule cap_refs_in_kernel_windowD2)
                           apply(simp add: invs_cap_refs_in_kernel_window)
                          apply(fastforce simp: cap_range_def)
                         apply(frule range_cover.range_cover_compare_bound)
                         apply(frule range_cover.unat_of_nat_n)
                         apply(simp add: shiftl_t2n)
                         apply(subst unat_mult_power_lem)
                          apply(erule range_cover.string)
                         apply(simp add: mult.commute)
                        apply(fastforce intro!: cte_wp_at_pas_cap_cur_auth_UntypedCap_idx)

                         apply (frule retype_addrs_subset_ptr_bits)
                         apply (clarsimp simp: authorised_untyped_inv_state_def)
                         apply (erule_tac x="UntypedCap word2 sz idx" in allE)
                         apply (force simp: ptr_range_def bits_of_UntypedCap p_assoc_help)

                       apply(fastforce dest: valid_global_refsD2 simp: cte_wp_at_caps_of_state)
                      apply(fastforce dest!: untyped_slots_not_in_untyped_range[OF _ _ _ _ _ subset_refl])
                     apply(clarsimp simp: authorised_untyped_inv_state_def)
                     apply(drule_tac x="UntypedCap word2 sz idx" in spec, fastforce simp: cte_wp_at_def ptr_range_def bits_of_UntypedCap pas_refined_refl p_assoc_help)
                    apply(erule ssubst[OF free_index_of_UntypedCap])
                   apply(subgoal_tac "usable_untyped_range
           (UntypedCap (word2 && ~~ mask sz) sz
             (unat
               ((word2 && mask sz) + of_nat (length list) * 2 ^ obj_bits_api apiobject_type nat))) \<inter>
          {word2..word2 +
                  of_nat (length list) * 2 ^ obj_bits_api apiobject_type nat -
                  1} =
          {}")
                     apply(subgoal_tac "word2 && mask sz = 0", clarsimp simp: shiftl_t2n mult.commute)
                    apply(erule subst, rule mask_neg_mask_is_zero)
                   apply(rule usable_range_disjoint, simp+)
                    apply(fastforce elim: ex_cte_cap_wp_to_weakenE)
                   apply assumption
                  apply(fastforce dest: range_cover_subset')
                 apply(rule ssubst[OF free_index_of_UntypedCap])
                 apply(fastforce simp: descendants_range_def2)
                apply(rule disjI2)
                apply(clarsimp simp: cte_wp_at_caps_of_state invs_def valid_state_def valid_pspace_def)
                apply(erule ssubst[OF free_index_of_UntypedCap])
               apply(rule disjI2)
               apply(clarsimp simp: cte_wp_at_caps_of_state invs_def valid_state_def valid_pspace_def)
               apply(erule ssubst[OF free_index_of_UntypedCap])

               apply (frule retype_addrs_subset_ptr_bits)
               apply clarsimp
               apply (frule(1) subsetD)
               apply(clarsimp simp: authorised_untyped_inv_state_def)
               apply(drule_tac x="UntypedCap (word2 && ~~ mask sz) sz idx" in spec, clarsimp simp: cte_wp_at_def ptr_range_def bits_of_UntypedCap pas_refined_refl word_and_le2)
               apply(erule bspec, simp add: p_assoc_help, erule order_trans[rotated])
               apply(fastforce simp: word_and_le2)

              apply(drule cap_refs_in_kernel_windowD2)
               apply(simp add: invs_cap_refs_in_kernel_window)
              apply(clarsimp simp: cap_range_def)
              apply(erule region_in_kernel_window_subseteq)
              apply(simp add: word_and_le2)
             apply(clarsimp simp: cte_wp_at_caps_of_state, drule valid_global_refsD2, simp add: invs_valid_global_refs, subst Int_commute, simp)
             apply(erule disjoint_subset2[rotated])
             apply(simp add: word_and_le2)
            apply(rule descendants_range_in_subseteq[OF cte_wp_at_caps_descendants_range_inI])
                apply (simp add: cte_wp_at_sym)+
            apply(fastforce dest: range_cover_subset')
           (* proof clagged from Untyped_R.invoke_untyped_proofs.idx_compare' *)
           apply(simp add: mask_out_sub_mask add.commute mult.commute)
           apply (rule le_trans[OF unat_plus_gt])
           apply(subst range_cover.unat_of_nat_n_shift, simp+)
           apply(simp add: range_cover.range_cover_compare_bound[simplified add.commute])

          apply(clarsimp simp: authorised_untyped_inv_state_def)
          apply(drule_tac x="UntypedCap (word2 && ~~ mask sz) sz idx" in spec, clarsimp simp: cte_wp_at_def ptr_range_def bits_of_UntypedCap pas_refined_refl word_and_le2)
          apply(erule bspec, simp add: p_assoc_help, erule order_trans[rotated])
          apply(fastforce simp: word_and_le2)
         apply(fastforce intro!: cte_wp_at_pas_cap_cur_auth_UntypedCap_idx)
        apply(simp add: free_index_of_UntypedCap)
       apply(simp add: shiftl_t2n mask_out_sub_mask add.commute mult.commute)
       apply(simp add: mask_out_sub_mask[symmetric])
       apply(rule usable_range_disjoint, simp+)
        apply(fastforce elim: ex_cte_cap_wp_to_weakenE)
       apply assumption
      apply(simp add: word_and_le2)
     apply(fastforce dest: range_cover_subset')
    apply(rule disjI1)
    apply(simp add: free_index_of_UntypedCap)
    apply(simp add: mask_out_sub_mask add.commute mult.commute shiftl_t2n)
    apply(erule order_trans)
    apply(simp add: range_cover_unat)
   apply(rule disjI2)
   apply(rule conjI)
    apply(rule cte_wp_at_pspace_no_overlapI, (simp add: cte_wp_at_sym)+)
   apply(rule conjI)
    apply(rule cte_wp_at_caps_descendants_range_inI, (simp add: cte_wp_at_sym)+)
    apply(clarsimp simp: cte_wp_at_def)
   apply(fastforce dest: cte_wp_at_valid_objs_valid_cap simp: valid_cap_def cap_aligned_def)
  done

subsection{* decode *}

lemma bang_0_in_set:
  "xs \<noteq> [] \<Longrightarrow> xs ! 0 \<in> set xs"
  apply(fastforce simp: in_set_conv_nth)
  done

lemma get_cap_ret_is_subject:
  "\<lbrace>(pas_refined aag) and K (is_subject aag (fst slot))\<rbrace>
   get_cap slot
   \<lbrace>\<lambda>rv s. is_cnode_cap rv \<longrightarrow> (is_subject aag (obj_ref_of rv))\<rbrace>"
  apply(clarsimp simp: valid_def)
  apply(frule get_cap_det)
  apply(drule_tac f=fst in arg_cong)
  apply(subst (asm) fst_conv)
  apply(drule in_get_cap_cte_wp_at[THEN iffD1])
  apply(clarsimp simp: cte_wp_at_caps_of_state)
  apply(rule caps_of_state_pasObjectAbs_eq)
      apply(blast intro: sym)
     apply(fastforce simp: cap_auth_conferred_def split: cap.split)
    apply assumption+
  apply(case_tac a, simp_all)
  done

lemma data_to_obj_type_ret_not_asid_pool:
  "\<lbrace> \<top> \<rbrace> data_to_obj_type arg \<lbrace> \<lambda>r s. r \<noteq> ArchObject ASIDPoolObj \<rbrace>,-"
  apply(clarsimp simp: validE_R_def validE_def valid_def)
  apply(auto simp: data_to_obj_type_def arch_data_to_obj_type_def throwError_def simp: returnOk_def bindE_def return_def bind_def lift_def split: split_if_asm)
  done

crunch inv[wp]: data_to_obj_type "P"

definition authorised_untyped_inv' where
 "authorised_untyped_inv' aag ui \<equiv> case ui of
     Invocations_A.untyped_invocation.Retype src_slot base aligned_free_ref new_type obj_sz slots \<Rightarrow>
       is_subject aag (fst src_slot) \<and> (0::word32) < of_nat (length slots) \<and>
       new_type \<noteq> ArchObject ASIDPoolObj \<and>
       (\<forall>x\<in>set slots. is_subject aag (fst x))"


lemma authorised_untyped_invI:
  notes blah[simp del] = atLeastAtMost_iff atLeastatMost_subset_iff atLeastLessThan_iff
          Int_atLeastAtMost atLeastatMost_empty_iff split_paired_Ex

  shows
  "\<lbrakk>valid_untyped_inv ui s; authorised_untyped_inv_state aag ui s;
        authorised_untyped_inv' aag ui\<rbrakk> \<Longrightarrow>
   authorised_untyped_inv aag ui"
  apply(case_tac ui)
  apply (rename_tac cslot_ptr word1 word2 apiobject_type nat list)
  apply(clarsimp simp: authorised_untyped_inv_state_def cte_wp_at_sym authorised_untyped_inv_def authorised_untyped_inv'_def)
  apply(drule_tac x="UntypedCap  (word2 && ~~ mask sz) sz idx" in spec, clarsimp simp: ptr_range_def bits_of_UntypedCap)
  apply(erule bspec)
  apply(erule subsetD[OF _ subsetD[OF range_cover_subset'], rotated])
    apply(simp add: blah word_and_le2)+
  done

lemma nonzero_unat_simp:
  "0 < unat (x::word32) \<Longrightarrow> 0 < x"
  apply(auto dest: word_of_nat_less)
  done

lemma decode_untyped_invocation_authorised:
   "\<lbrace>invs and pas_refined aag and valid_cap cap
        and cte_wp_at (op = cap) slot
        and (\<lambda>s. \<forall>cap\<in>set excaps.
                  is_cnode_cap cap \<longrightarrow>
                   (\<forall>r\<in>cte_refs cap (interrupt_irq_node s).
                       ex_cte_cap_wp_to is_cnode_cap r s))
        and (\<lambda>s. \<forall>x\<in>set excaps. s \<turnstile> x)
        and K (cap = cap.UntypedCap base sz idx
               \<and> is_subject aag (fst slot)
               \<and> (\<forall>c \<in> set excaps. pas_cap_cur_auth aag c)
               \<and> (\<forall> ref \<in> untyped_range cap. is_subject aag ref))\<rbrace>
     decode_untyped_invocation label args slot cap excaps
   \<lbrace>\<lambda>rv s. authorised_untyped_inv aag rv \<and> authorised_untyped_inv_state aag rv s\<rbrace>,-"
  apply (rule_tac Q'="\<lambda> rv s. valid_untyped_inv rv s \<and> authorised_untyped_inv_state aag rv s \<and> authorised_untyped_inv' aag rv" in hoare_post_imp_R)
   prefer 2
   apply(blast intro: authorised_untyped_invI)
  apply(rule hoare_gen_asmE)
   apply(rule hoare_pre)
   apply(wp dui_inv_wf | simp)+
  apply (clarsimp simp: decode_untyped_invocation_def split_def
                        authorised_untyped_inv'_def
                        authorised_untyped_inv_state_def
                  split del: split_if split: untyped_invocation.splits)
  (* need to hoist the is_cnode_cap assumption into postcondition later on *)

  apply (simp add: unlessE_def[symmetric] whenE_def[symmetric] unlessE_whenE
           split del: split_if)
  apply (wp whenE_throwError_wp  hoare_vcg_all_lift mapME_x_inv_wp
        | simp split: untyped_invocation.splits
        | (auto)[1])+
           apply (rule_tac Q="\<lambda>node_cap s.
             (is_cnode_cap node_cap \<longrightarrow> is_subject aag (obj_ref_of node_cap)) \<and>
             is_subject aag (fst slot) \<and>
             new_type \<noteq> ArchObject ASIDPoolObj \<and>
             (\<forall> cap. cte_wp_at (op = cap) slot s \<longrightarrow>
                (\<forall>ref\<in>ptr_range base (bits_of cap). is_subject aag ref))"
                       in hoare_strengthen_post)
            apply (wp get_cap_inv get_cap_ret_is_subject)
           apply (fastforce simp: nonzero_unat_simp)
          apply(clarsimp simp: K_def)
          apply(wp lookup_slot_for_cnode_op_authorised
                   lookup_slot_for_cnode_op_inv whenE_throwError_wp)
     apply(rule hoare_drop_imps)+
     apply(clarsimp)
     apply(rule_tac Q'="\<lambda>rv s. rv \<noteq> ArchObject ASIDPoolObj \<and>
                               (\<forall> cap. cte_wp_at (op = cap) slot s \<longrightarrow>
                                 (\<forall>ref\<in>ptr_range base (bits_of cap). is_subject aag ref)) \<and>
                              is_subject aag (fst slot) \<and>
                          pas_refined aag s \<and> 2 \<le> sz \<and>
                          sz < word_bits \<and> is_aligned base sz \<and>
                          (is_cnode_cap (excaps ! 0) \<longrightarrow>
                            (\<forall> x\<in>obj_refs (excaps ! 0). is_subject aag x))"
                 in hoare_post_imp_R)
      apply(wp data_to_obj_type_ret_not_asid_pool data_to_obj_type_inv2)
     apply(case_tac "excaps ! 0", simp_all, fastforce simp: nonzero_unat_simp)[1]
    apply(wp whenE_throwError_wp)
  apply(auto dest!: bang_0_in_set
              simp: valid_cap_def cap_aligned_def obj_ref_of_def is_cap_simps
                    cap_auth_conferred_def pas_refined_all_auth_is_owns
                    aag_cap_auth_def ptr_range_def
             dest: cte_wp_at_eqD2 simp: bits_of_UntypedCap)
  done

end

end