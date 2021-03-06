(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory DetSchedAux_AI
imports DetSchedInvs_AI
begin

context begin interpretation Arch .
requalify_facts
  invoke_untyped_st_tcb_at
end

crunch_ignore (del:
  cap_swap_ext cap_move_ext cap_insert_ext empty_slot_ext create_cap_ext tcb_sched_action
  reschedule_required set_thread_state_ext switch_if_required_to
  attempt_switch_to timer_tick set_priority retype_region_ext)

crunch_ignore (add: do_extended_op)

crunch ekheap[wp]: update_cdt_list "\<lambda>s. P (ekheap s)"
crunch rqueues[wp]: update_cdt_list "\<lambda>s. P (ready_queues s)"
crunch schedact[wp]: update_cdt_list "\<lambda>s. P (scheduler_action s)"
crunch cur_domain[wp]: update_cdt_list "\<lambda>s. P (cur_domain s)"

crunch ekheap[wp]: create_cap, cap_insert "\<lambda>s :: det_ext state. P (ekheap s)" (wp: crunch_wps)

crunch rqueues[wp]: create_cap, cap_insert "\<lambda>s :: det_ext state. P (ready_queues s)" (wp: crunch_wps)

crunch schedact[wp]: create_cap, cap_insert "\<lambda>s :: det_ext state. P (scheduler_action s)" (wp: crunch_wps)

crunch cur_domain[wp]: create_cap, cap_insert "\<lambda>s :: det_ext state. P (cur_domain s)" (wp: crunch_wps)

lemma create_cap_ct[wp]: "\<lbrace>\<lambda>s. P (cur_thread s)\<rbrace> create_cap a b c d \<lbrace>\<lambda>r s. P (cur_thread s)\<rbrace>"
  apply (simp add: create_cap_def)
  apply (rule hoare_pre)
   apply (wp dxo_wp_weak | wpc | simp)+
  done

crunch valid_etcbs[wp]: create_cap,cap_insert,set_cap valid_etcbs (wp: valid_etcbs_lift set_cap_typ_at)

lemma valid_etcb_fold_update: "valid_etcbs_2 ekh kh \<Longrightarrow> type \<noteq> apiobject_type.Untyped \<Longrightarrow> valid_etcbs_2
          (foldr (\<lambda>p ekh. ekh(p := default_ext type cdom))
            ptrs
            ekh)
          (foldr (\<lambda>p kh. kh(p \<mapsto> default_object type o_bits))
            ptrs
            kh)"
  apply (induct ptrs)
  apply simp
  apply (case_tac type)
  apply (clarsimp simp add: valid_etcbs_def st_tcb_at_kh_def obj_at_kh_def obj_at_def is_etcb_at_def default_object_def default_ext_def)+
  done

(*
lemma valid_etcb_fold_update': "valid_etcbs_2 ekh kh \<Longrightarrow> \<not> is_tcb new_obj \<Longrightarrow> valid_etcbs_2
          ekh
          (foldr (\<lambda>p kh. kh(p \<mapsto> new_obj))
            ptrs
            kh)"
  apply (induct ptrs)
  apply simp
  apply (simp add: valid_etcbs_def)


  apply (clarsimp simp add: valid_etcbs_def st_tcb_at_kh_def obj_at_kh_def obj_at_def is_etcb_at_def default_object_def)+
  apply force
  done

thm valid_queues_def

lemma valid_queues_fold_update: "\<forall>ptr \<in> set ptrs. \<forall>p. ptr \<notin> set (queues p) \<Longrightarrow> valid_queues_2 queues ekh kh \<Longrightarrow> valid_queues_2 queues
          (foldr (\<lambda>p ekh. ekh(p \<mapsto> default_etcb))
            ptrs
            ekh)
          (foldr (\<lambda>p kh. kh(p \<mapsto> default_object TCBObject o_bits))
            ptrs
            kh)"
  apply (induct ptrs)
  apply (clarsimp simp add: valid_queues_def st_tcb_at_kh_def obj_at_kh_def obj_at_def is_etcb_at_def default_object_def etcb_at_def)+
  done

thm valid_sched_def
thm kernel_object.cases
lemma valid_sched_action_fold_update: "\<forall>ptr \<in> set ptrs. ptr \<noteq> ct \<and> kh ptr = None \<Longrightarrow>
         valid_sched_action_2 sa kh ct \<Longrightarrow>
          valid_sched_action_2 sa (foldr (\<lambda>p kh. kh(p \<mapsto> default_object TCBObject o_bits))
            ptrs
            kh) ct"
   apply (induct ptrs)
  apply (clarsimp simp add: valid_sched_action_def is_activatable_def weak_valid_sched_action_def st_tcb_at_kh_def obj_at_kh_def obj_at_def is_etcb_at_def default_object_def etcb_at_def)+
  done

lemma valid_sched_fold_update: "\<forall>ptr \<in> set ptrs. ptr \<noteq> ct \<and> kh ptr = None \<Longrightarrow> valid_sched_2 queues ekh sa kh ct \<Longrightarrow>
         valid_sched_2 queues (foldr (\<lambda>p ekh. ekh(p \<mapsto> default_etcb))
            ptrs
            ekh) sa (foldr (\<lambda>p kh. kh(p \<mapsto> default_object TCBObject o_bits))
            ptrs
            kh) ct"
  apply (simp add: valid_sched_2_def valid_etcb_fold_update valid_sched_action_fold_update)
  apply (fastforce intro: valid_queues_fold_update simp: valid_queues_def st_tcb_at_kh_def obj_at_kh_def obj_at_def)
  done*)

lemma retype_etcb_at_helper: "\<lbrakk>etcb_at' P t ekh; valid_etcbs_2 ekh kh; d \<noteq> apiobject_type.Untyped;
        foldr (\<lambda>p kh. kh(p \<mapsto> default_object d c))
         ptrs
         kh t =
        Some (TCB tcb);
        tcb_state tcb \<noteq> Inactive\<rbrakk>
       \<Longrightarrow> etcb_at' P t
           ((foldr (\<lambda>p ekh. ekh(p := default_ext d cdom))
             ptrs)
             ekh)"
  apply (induct ptrs)
  apply simp
  apply (case_tac d)
  apply (clarsimp split: split_if_asm simp: default_tcb_def default_object_def default_ext_def etcb_at'_def)+
  done

lemma retype_region_etcb_at:"\<lbrace>(\<lambda>s. etcb_at P t s) and valid_etcbs\<rbrace> retype_region a b c d \<lbrace>\<lambda>r s. st_tcb_at (Not o inactive) t s \<longrightarrow> etcb_at P t s\<rbrace> "
  apply (simp add: retype_region_def)
  apply (simp add: retype_region_ext_def bind_assoc)
  apply wp
  apply (clarsimp simp add: pred_tcb_at_def obj_at_def simp del: fun_upd_apply)
  apply (blast intro: retype_etcb_at_helper)
  done

lemma retype_region_valid_etcbs[wp]:"\<lbrace>valid_etcbs\<rbrace> retype_region a b c d \<lbrace>\<lambda>_. valid_etcbs\<rbrace>"
  apply (simp add: retype_region_def)
  apply (simp add: retype_region_ext_def bind_assoc)
  apply wp
  apply (clarsimp simp del: fun_upd_apply)
  apply (blast intro: valid_etcb_fold_update)
  done

lemma typ_at_pred_tcb_at_lift: 
  assumes typ_lift: "\<And>P T p. \<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace> f \<lbrace>\<lambda>r s. P (typ_at T p s)\<rbrace>"
  assumes pred_lift: "\<And>P. \<lbrace>pred_tcb_at proj P t\<rbrace> f \<lbrace>\<lambda>_. pred_tcb_at proj P t\<rbrace>"
  shows "\<lbrace>\<lambda>s. \<not> pred_tcb_at proj P t s\<rbrace> f \<lbrace>\<lambda>r s. \<not> pred_tcb_at proj P t s\<rbrace>"

  apply (simp add: valid_def obj_at_def pred_tcb_at_def)
  apply clarsimp
  apply (case_tac "kheap s t")
   apply (cut_tac P="\<lambda>x. \<not> x" and p=t and T="ATCB" in typ_lift)
   apply (simp add: valid_def obj_at_def)
   apply force
  apply (cut_tac P="\<lambda>x. x" and p=t and T="a_type aa" in typ_lift)
  apply (cut_tac P="\<lambda>t. \<not> P t" in pred_lift)
  apply (simp add: valid_def obj_at_def pred_tcb_at_def)
  apply (drule_tac x=s in spec)
  apply simp
  apply (drule_tac x="(a,b)" in bspec)
   apply simp
  apply simp
  apply (subgoal_tac "a_type aa = ATCB")
   apply (erule a_type_ATCBE)
   apply simp
   apply force
  apply simp
  done


lemma create_cap_no_pred_tcb_at: "\<lbrace>\<lambda>s. \<not> pred_tcb_at proj P t s\<rbrace>
          create_cap apiobject_type nat' prod' x
          \<lbrace>\<lambda>r s. \<not> pred_tcb_at proj P t s\<rbrace>"
  apply (rule typ_at_pred_tcb_at_lift)
  apply wp
  done

lemma cap_insert_no_pred_tcb_at: "\<lbrace>\<lambda>s. \<not> pred_tcb_at proj P t s\<rbrace>
          cap_insert cap src dest
          \<lbrace>\<lambda>r s. \<not> pred_tcb_at proj P t s\<rbrace>"
  apply (rule typ_at_pred_tcb_at_lift)
  apply wp
  done


locale DetSchedAux_AI =
  fixes state_ext_t :: "'state_ext::state_ext itself"
  assumes invoke_untyped_ct[wp]:
    "\<And>P i. \<lbrace>\<lambda>s::'state_ext state. P (cur_thread s)\<rbrace> invoke_untyped i \<lbrace>\<lambda>_ s. P (cur_thread s)\<rbrace>"
  assumes invoke_untyped_idle_thread[wp]:
    "\<And>P i. \<lbrace>\<lambda>s::'state_ext state. P (idle_thread s)\<rbrace> invoke_untyped i \<lbrace>\<lambda>_ s. P (idle_thread s)\<rbrace>"

locale DetSchedAux_AI_det_ext = DetSchedAux_AI "TYPE(det_ext)" +
  assumes delete_objects_etcb_at[wp]:
    "\<And>P t a b. \<lbrace>\<lambda>s::det_ext state. etcb_at P t s\<rbrace> delete_objects a b \<lbrace>\<lambda>r s. etcb_at P t s\<rbrace>"
  assumes invoke_untyped_etcb_at:
    "\<And>P t ui.
      \<lbrace>(\<lambda>s :: det_ext state. etcb_at P t s) and valid_etcbs\<rbrace>
        invoke_untyped ui
      \<lbrace>\<lambda>r s. st_tcb_at (Not o inactive) t s \<longrightarrow> etcb_at P t s\<rbrace> "
  assumes init_arch_objects_valid_etcbs[wp]:
    "\<And>t r n sz refs. \<lbrace>valid_etcbs\<rbrace> init_arch_objects t r n sz refs \<lbrace>\<lambda>_. valid_etcbs\<rbrace>"
  assumes init_arch_objects_valid_blocked[wp]:
    "\<And>t r n sz refs. \<lbrace>valid_blocked\<rbrace> init_arch_objects t r n sz refs \<lbrace>\<lambda>_. valid_blocked\<rbrace>"
  assumes invoke_untyped_cur_domain[wp]:
    "\<And>P i. \<lbrace>\<lambda>s. P (cur_domain s)\<rbrace> invoke_untyped i \<lbrace>\<lambda>_ s. P (cur_domain s)\<rbrace>"
  assumes invoke_untyped_ready_queues[wp]:
    "\<And>P i. \<lbrace>\<lambda>s. P (ready_queues s)\<rbrace> invoke_untyped i \<lbrace>\<lambda>_ s. P (ready_queues s)\<rbrace>"
  assumes invoke_untyped_scheduler_action[wp]:
    "\<And>P i. \<lbrace>\<lambda>s. P (scheduler_action s)\<rbrace> invoke_untyped i \<lbrace>\<lambda>_ s. P (scheduler_action s)\<rbrace>"

lemma delete_objects_valid_etcbs[wp]: "\<lbrace>valid_etcbs\<rbrace> delete_objects a b \<lbrace>\<lambda>_. valid_etcbs\<rbrace>"
  apply (simp add: delete_objects_def)
  apply wp
  apply (simp add: detype_def detype_ext_def wrap_ext_det_ext_ext_def)
  apply (rule hoare_pre)
   apply (simp add: do_machine_op_def)
   apply (wp|wpc)+
  apply (simp add: valid_etcbs_def st_tcb_at_kh_def obj_at_kh_def obj_at_def is_etcb_at_def)
  done


context DetSchedAux_AI_det_ext begin

lemma invoke_untyped_valid_etcbs[wp]: "\<lbrace>valid_etcbs\<rbrace> invoke_untyped ui \<lbrace>\<lambda>_.valid_etcbs\<rbrace>"
  apply (cases ui)
  apply (simp add: mapM_x_def[symmetric])
  apply (wp mapM_x_wp')
  apply simp
  done

end


crunch valid_blocked[wp]: create_cap,cap_insert,set_cap valid_blocked
  (wp: valid_blocked_lift set_cap_typ_at)

lemma valid_blocked_fold_update: "valid_blocked_2 queues kh sa ct \<Longrightarrow> type \<noteq> apiobject_type.Untyped \<Longrightarrow> valid_blocked_2
          queues
          (foldr (\<lambda>p kh. kh(p \<mapsto> default_object type o_bits))
            ptrs
            kh) sa ct"
  apply (induct ptrs)
   apply simp
  apply (case_tac type)
       apply simp
      apply (clarsimp,
             clarsimp simp: valid_blocked_def st_tcb_at_kh_def obj_at_kh_def obj_at_def
                            default_object_def default_tcb_def)+
      done

lemma retype_region_valid_blocked[wp]:
  "\<lbrace>valid_blocked\<rbrace> retype_region a b c d \<lbrace>\<lambda>_. valid_blocked\<rbrace>"
  apply (simp add: retype_region_def)
  apply (simp add: retype_region_ext_def bind_assoc)
  apply wp
  apply (clarsimp simp del: fun_upd_apply)
  apply (blast intro: valid_blocked_fold_update)
  done

lemma delete_objects_valid_blocked[wp]: "\<lbrace>valid_blocked\<rbrace> delete_objects a b \<lbrace>\<lambda>_. valid_blocked\<rbrace>"
  apply (simp add: delete_objects_def)
  apply wp
  apply (simp add: detype_def detype_ext_def wrap_ext_det_ext_ext_def)
  apply (rule hoare_pre)
   apply (simp add: do_machine_op_def)
   apply (wp|wpc)+
  apply (simp add: valid_blocked_def st_tcb_at_kh_def obj_at_kh_def obj_at_def is_etcb_at_def)
  done

context DetSchedAux_AI_det_ext begin

lemma invoke_untyped_valid_blocked[wp]: "\<lbrace>valid_blocked\<rbrace> invoke_untyped ui \<lbrace>\<lambda>_.valid_blocked\<rbrace>"
  apply (cases ui)
  apply (simp add: mapM_x_def[symmetric])
  apply (wp mapM_x_wp')
  apply simp
  done

end

(*Leverages the fact that retype only clears out inactive tcbs under
  the invariants*)
lemma valid_sched_tcb_state_preservation:
  assumes st_tcb: "\<And>P t. \<lbrace>I and ct_active and st_tcb_at (P and Not o inactive and Not o idle) t\<rbrace> f \<lbrace>\<lambda>_.st_tcb_at P t\<rbrace>"
  assumes stuff: "\<And>P t. \<lbrace>(\<lambda>s. etcb_at P t s) and valid_etcbs\<rbrace> f \<lbrace>\<lambda>r s. st_tcb_at (Not o inactive) t s \<longrightarrow> etcb_at P t s\<rbrace>"
  assumes cur_thread: "\<And>P. \<lbrace>\<lambda>s. P (cur_thread s)\<rbrace> f \<lbrace>\<lambda>r s. P (cur_thread s)\<rbrace>"
  assumes idle_thread: "\<And>P. \<lbrace>\<lambda>s. P (idle_thread s)\<rbrace> f \<lbrace>\<lambda>r s. P (idle_thread s)\<rbrace>"
  assumes valid_etcb: "\<lbrace>valid_etcbs\<rbrace> f \<lbrace>\<lambda>_. valid_etcbs\<rbrace>"
  assumes valid_blocked: "\<lbrace>valid_blocked\<rbrace> f \<lbrace>\<lambda>_. valid_blocked\<rbrace>"
  assumes valid_idle: "\<lbrace>I\<rbrace> f \<lbrace>\<lambda>_. valid_idle\<rbrace>"
  assumes valid_others: "\<And>P. \<lbrace>\<lambda>s. P (scheduler_action s) (ready_queues s) (cur_domain s)\<rbrace> f \<lbrace>\<lambda>r s. P (scheduler_action s) (ready_queues s) (cur_domain s)\<rbrace>"
  shows "\<lbrace>I and ct_active and valid_sched and valid_idle\<rbrace> f \<lbrace>\<lambda>_. valid_sched\<rbrace>"
  apply (clarsimp simp add: valid_sched_def valid_def)
  apply (frule(1) use_valid[OF _ valid_etcb])
  apply (frule(1) use_valid[OF _ valid_blocked])
  apply simp
  apply (frule_tac P1="\<lambda>sa rq cdom. rq = ready_queues s \<and> sa = scheduler_action s \<and> cdom = cur_domain s" in use_valid[OF _ valid_others])
   apply simp
  apply (rule conjI)
   apply (clarsimp simp add: valid_queues_def)
   apply (drule_tac x=d in spec)
   apply (drule_tac x=p in spec)
   apply clarsimp
   apply (drule_tac x=t in bspec)
    apply simp
   apply clarsimp
   apply (subgoal_tac "st_tcb_at runnable t b")
    apply simp
    apply (rule conjI)
     apply (fastforce simp: valid_etcbs_def pred_tcb_at_def obj_at_def)
    apply (frule_tac P1="(\<lambda>t. tcb_priority t = p \<and> tcb_domain t = d)" and t1=t in use_valid[OF _ stuff])
     apply simp
    apply (simp add: pred_tcb_at_def obj_at_def)
    apply force
   apply (rule_tac use_valid[OF _ st_tcb],assumption)
   apply simp
   apply (erule pred_tcb_weakenE)
   apply simp
   apply (case_tac "itcb_state tcb")
          apply simp+
  apply (frule_tac P1="\<lambda>ct. ct = (cur_thread s)" in use_valid[OF _ cur_thread])
   apply simp
  apply (rule conjI)
   apply simp
  apply simp
  apply (clarsimp simp add: valid_sched_action_def is_activatable_def weak_valid_sched_action_def)
  apply (rule conjI)
   apply clarsimp
   apply (frule_tac P1="active" and t1="cur_thread s" in use_valid[OF _ st_tcb])
    apply (simp add: ct_in_state_def)
    apply (erule pred_tcb_weakenE)
    apply simp
    apply (case_tac "itcb_state tcb")
           apply simp+
   apply (erule pred_tcb_weakenE)
   apply (case_tac "itcb_state tcb")
          apply simp+
  apply (rule conjI)
   apply clarsimp
   apply (rule_tac use_valid[OF _ st_tcb],assumption)
   apply simp
  apply (erule pred_tcb_weakenE)
   apply simp
   apply (case_tac "itcb_state tcb", simp+)
  apply (rule conjI)
   apply (clarsimp simp: switch_in_cur_domain_def in_cur_domain_def)
   apply (rule use_valid[OF _ stuff, rule_format], assumption)
    apply simp
   apply (rule use_valid[OF _ st_tcb], assumption)
   apply simp
   apply (erule st_tcb_weakenE)
   apply (case_tac st, simp+)
  apply (clarsimp simp: ct_in_cur_domain_2_def in_cur_domain_2_def)
  apply (frule_tac P1="\<lambda>idle. idle = (idle_thread s)" in use_valid[OF _ idle_thread], simp)
  apply (rule conjI)
   apply (rule impI)
   apply (simp, erule disjE, simp)
   apply (frule_tac P1="(\<lambda>t. tcb_domain t = cur_domain s)" and t1="cur_thread s" in use_valid[OF _ stuff])
    apply (clarsimp simp: etcb_at_def split: option.splits)
   apply clarsimp
   apply (erule notE, rule use_valid[OF _ st_tcb],assumption)
   apply (simp add: ct_in_state_def)
   apply (erule st_tcb_weakenE)
   apply simp
   apply (case_tac st, simp+)
  apply(frule (1) use_valid[OF _ valid_idle])
  apply(simp add: valid_idle_etcb_def)  
  apply(frule use_valid[OF _ stuff[where t=idle_thread_ptr]])
   apply simp
  apply(erule mp)
  apply(fastforce simp: valid_idle_def pred_tcb_at_def obj_at_def)
  done

lemmas mapM_x_defsym = mapM_x_def[symmetric]

lemma valid_idle_etcb_lift:
  assumes "\<And>P t. \<lbrace>\<lambda>s. etcb_at P t s\<rbrace> f \<lbrace>\<lambda>r s. etcb_at P t s\<rbrace>"
  shows "\<lbrace>valid_idle_etcb\<rbrace> f \<lbrace>\<lambda>r. valid_idle_etcb\<rbrace>"
  apply(simp add: valid_idle_etcb_def)
  apply(wp assms)
  done


context DetSchedAux_AI_det_ext begin

lemma invoke_untyped_valid_sched:
  "\<lbrace>invs and valid_untyped_inv ui and ct_active and valid_sched and valid_idle \<rbrace>
     invoke_untyped ui
   \<lbrace> \<lambda>_ . valid_sched \<rbrace>"
  apply (rule hoare_pre)
   apply (rule_tac I="invs and valid_untyped_inv ui and ct_active" in valid_sched_tcb_state_preservation)
          apply (wp invoke_untyped_st_tcb_at)
          apply simp
         apply (wp invoke_untyped_etcb_at)
    apply (rule hoare_strengthen_post)
     apply (wp invoke_untyp_invs, simp add: invs_def valid_state_def)
   apply (rule_tac f="\<lambda>s. P (scheduler_action s)" in hoare_lift_Pf)
    apply (rule_tac f="\<lambda>s. x (ready_queues s)" in hoare_lift_Pf)
     apply wp
  apply simp
  done

end


lemma hoare_imp_lift_something: "\<lbrakk>\<lbrace>\<lambda>s. \<not> P s \<rbrace> f \<lbrace>\<lambda>r s. \<not> P s\<rbrace>;\<lbrace>Q\<rbrace> f \<lbrace>\<lambda>_.Q\<rbrace>\<rbrakk> \<Longrightarrow> \<lbrace>\<lambda>s. P s \<longrightarrow> Q s\<rbrace> f \<lbrace>\<lambda>r s. P s \<longrightarrow> Q s\<rbrace>"
  apply (clarsimp simp add: valid_def)
  apply force
  done

crunch valid_queues[wp]: create_cap,cap_insert valid_queues
  (wp: valid_queues_lift)

crunch valid_sched_action[wp]: create_cap,cap_insert valid_sched_action
  (wp: valid_sched_action_lift)

crunch valid_sched[wp]: create_cap,cap_insert valid_sched
  (wp: valid_sched_lift)

end
