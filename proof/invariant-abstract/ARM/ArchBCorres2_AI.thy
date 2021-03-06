(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory ArchBCorres2_AI
imports
  "../BCorres2_AI"
begin

context Arch begin global_naming ARM

named_theorems BCorres2_AI_assms

crunch (bcorres)bcorres[wp, BCorres2_AI_assms]: invoke_cnode truncate_state
  (simp: swp_def ignore: clearMemory without_preemption filterM ethread_set recycle_cap_ext)

crunch (bcorres)bcorres[wp]: create_cap,init_arch_objects,retype_region,delete_objects truncate_state
  (ignore: freeMemory clearMemory retype_region_ext)

crunch (bcorres)bcorres[wp]: set_extra_badge,derive_cap truncate_state (ignore: storeWord)

lemma invoke_untyped_bcorres[wp]:" bcorres (invoke_untyped a) (invoke_untyped a)"
  apply (cases a)
  apply (wp | simp)+
  done

lemma invoke_tcb_bcorres[wp]:
  fixes a
  shows "bcorres (invoke_tcb a) (invoke_tcb a)"
  apply (cases a)
        apply (wp | wpc | simp)+
  apply (rename_tac option)
  apply (case_tac option)
   apply (wp | wpc | simp)+
  done

lemma transfer_caps_loop_bcorres[wp]:
 "bcorres (transfer_caps_loop ep buffer n caps slots mi) (transfer_caps_loop ep buffer n caps slots mi)"
  apply (induct caps arbitrary: slots n mi ep)
   apply simp
   apply wp
  apply (case_tac a)
  apply simp
  apply (intro impI conjI)
             apply (wp | simp)+
  done

lemma invoke_irq_control_bcorres[wp]: "bcorres (invoke_irq_control a) (invoke_irq_control a)"
  apply (cases a)
  apply (wp | simp add: arch_invoke_irq_control_def)+
  done

lemma invoke_irq_handler_bcorres[wp]: "bcorres (invoke_irq_handler a) (invoke_irq_handler a)"
  apply (cases a)
  apply (wp | simp)+
  done

crunch (bcorres)bcorres[wp]: send_ipc,send_signal,do_reply_transfer,arch_perform_invocation truncate_state
  (simp: gets_the_def swp_def ignore: freeMemory clearMemory get_register loadWord cap_fault_on_failure
         set_register storeWord lookup_error_on_failure getRestartPC getRegister mapME)

lemma perform_invocation_bcorres[wp]: "bcorres (perform_invocation a b c) (perform_invocation a b c)"
  apply (cases c)
  apply (wp | wpc | simp)+
  done

lemma decode_cnode_invocation[wp]: "bcorres (decode_cnode_invocation a b c d) (decode_cnode_invocation a b c d)"
  apply (simp add: decode_cnode_invocation_def)
  apply (wp | wpc | simp add: split_def | intro impI conjI)+
  done

crunch (bcorres)bcorres[wp]: decode_set_ipc_buffer,decode_set_space,decode_set_priority,decode_bind_notification,decode_unbind_notification truncate_state

lemma decode_tcb_configure_bcorres[wp]: "bcorres (decode_tcb_configure b (cap.ThreadCap c) d e)
     (decode_tcb_configure b (cap.ThreadCap c) d e)"
  apply (simp add: decode_tcb_configure_def | wp)+
  done

lemma decode_tcb_invocation_bcorres[wp]:"bcorres (decode_tcb_invocation a b (cap.ThreadCap c) d e) (decode_tcb_invocation a b (cap.ThreadCap c) d e)"
  apply (simp add: decode_tcb_invocation_def)
  apply (wp | wpc | simp)+
  done

lemma create_mapping_entries_bcorres[wp]: "bcorres (create_mapping_entries a b c d e f) (create_mapping_entries a b c d e f)"
  apply (cases c)
  apply (wp | simp)+
  done

lemma ensure_safe_mapping_bcorres[wp]: "bcorres (ensure_safe_mapping a) (ensure_safe_mapping a)"
  apply (induct rule: ensure_safe_mapping.induct)
  apply (wp | wpc | simp)+
  done

crunch (bcorres)bcorres[wp]: handle_invocation truncate_state (simp:  Syscall_A.syscall_def Let_def gets_the_def ignore: get_register Syscall_A.syscall cap_fault_on_failure set_register without_preemption const_on_failure)

crunch (bcorres)bcorres[wp]: receive_ipc,receive_signal,delete_caller_cap truncate_state

lemma handle_vm_fault_bcorres[wp]: "bcorres (handle_vm_fault a b) (handle_vm_fault a b)"
  apply (cases b)
  apply (simp | wp)+
  done

lemma handle_event_bcorres[wp]: "bcorres (handle_event e) (handle_event e)"
  apply (cases e)
  apply (simp add: handle_send_def handle_call_def handle_recv_def handle_reply_def handle_yield_def handle_interrupt_def Let_def | intro impI conjI allI | wp | wpc)+
  done

crunch (bcorres)bcorres[wp]: guarded_switch_to,switch_to_idle_thread truncate_state (ignore: storeWord clearExMonitor)

lemma choose_switch_or_idle:
  "((), s') \<in> fst (choose_thread s) \<Longrightarrow>
       (\<exists>word. ((),s') \<in> fst (guarded_switch_to word s)) \<or>
       ((),s') \<in> fst (switch_to_idle_thread s)"
  apply (simp add: choose_thread_def)
  apply (clarsimp simp add: switch_to_idle_thread_def bind_def gets_def
                   arch_switch_to_idle_thread_def in_monad
                   return_def get_def modify_def put_def
                    get_thread_state_def
                   thread_get_def
                   split: split_if_asm)
  apply force
  done

end

end
