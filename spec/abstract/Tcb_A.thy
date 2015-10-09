(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

(* 
The TCB and thread related specifications.
*)

chapter "Threads and TCBs"

theory Tcb_A
imports Schedule_A
begin

section "Activating Threads"

text {* Threads that are active always have a master Reply capability to
themselves stored in their reply slot. This is so that a derived Reply
capability can be generated immediately if they wish to issue one. This function
sets up a new master Reply capability if one does not exist. *}
definition
  "setup_reply_master thread \<equiv> do
     old_cap <- get_cap (thread, tcb_cnode_index 2);
     when (old_cap = NullCap) $ do
         set_original (thread, tcb_cnode_index 2) True;
         set_cap (ReplyCap thread True) (thread, tcb_cnode_index 2)
     od
  od"

text {* Reactivate a thread if it is not already running. *}
definition
  restart :: "obj_ref \<Rightarrow> (unit,'z::state_ext) s_monad" where
 "restart thread \<equiv> do
    state \<leftarrow> get_thread_state thread;
    when (\<not> runnable state \<and> \<not> idle state) $ do
      ipc_cancel thread;
      setup_reply_master thread;
      set_thread_state thread Restart;
      do_extended_op (tcb_sched_action (tcb_sched_enqueue) thread);
      do_extended_op (switch_if_required_to thread)
    od
  od"

text {* This action is performed at the end of a system call immediately before
control is restored to a used thread. If it needs to be restarted then its
program counter is set to the operation it was performing rather than the next
operation. The idle thread is handled specially. *}
definition
  activate_thread :: "(unit,'z::state_ext) s_monad" where
  "activate_thread \<equiv> do
     thread \<leftarrow> gets cur_thread;
     state \<leftarrow> get_thread_state thread;
     (case state
       of Running \<Rightarrow> return ()
        | Restart \<Rightarrow> (do
            pc \<leftarrow> as_user thread getRestartPC;
            as_user thread $ setNextPC pc;
            set_thread_state thread Running
          od)
        | IdleThreadState \<Rightarrow> arch_activate_idle_thread thread
        | _ \<Rightarrow> fail)
   od"

section "Thread Message Formats"

text {* The number of message registers in a maximum length message. *}
definition
  number_of_mrs :: nat where
 "number_of_mrs \<equiv> 32"

text {* The size of a user IPC buffer. *}
definition
  ipc_buffer_size :: vspace_ref where
 "ipc_buffer_size \<equiv> of_nat ((number_of_mrs + captransfer_size) * word_size)"

definition
  load_word_offs :: "obj_ref \<Rightarrow> nat \<Rightarrow> (machine_word,'z::state_ext) s_monad" where
 "load_word_offs ptr offs \<equiv>
    do_machine_op $ loadWord (ptr + of_nat (offs * word_size))"
definition
  load_word_offs_word :: "obj_ref \<Rightarrow> data \<Rightarrow> (machine_word,'z::state_ext) s_monad" where
 "load_word_offs_word ptr offs \<equiv>
    do_machine_op $ loadWord (ptr + (offs * word_size))"

text {* Get all of the message registers, both from the sending thread's current
register file and its IPC buffer. *}
definition
  get_mrs :: "obj_ref \<Rightarrow> obj_ref option \<Rightarrow> message_info \<Rightarrow> 
              (message list,'z::state_ext) s_monad" where
  "get_mrs thread buf info \<equiv> do
     context \<leftarrow> thread_get tcb_context thread;
     cpu_mrs \<leftarrow> return (map context msg_registers);
     buf_mrs \<leftarrow> case buf
       of None      \<Rightarrow> return []
        | Some pptr \<Rightarrow> mapM (\<lambda>x. load_word_offs pptr x)
               [length msg_registers + 1 ..< Suc msg_max_length];
     return (take (unat (mi_length info)) $ cpu_mrs @ buf_mrs)
   od"

text {* Copy message registers from one thread to another. *}
definition
  copy_mrs :: "obj_ref \<Rightarrow> obj_ref option \<Rightarrow> obj_ref \<Rightarrow>
               obj_ref option \<Rightarrow> length_type \<Rightarrow> (length_type,'z::state_ext) s_monad" where
  "copy_mrs sender sbuf receiver rbuf n \<equiv>
   do
     hardware_mrs \<leftarrow> return $ take (unat n) msg_registers;
     mapM (\<lambda>r. do
         v \<leftarrow> as_user sender $ get_register r;
         as_user receiver $ set_register r v
       od) hardware_mrs;
     buf_mrs \<leftarrow> case (sbuf, rbuf) of
       (Some sb_ptr, Some rb_ptr) \<Rightarrow> mapM (\<lambda>x. do
                                       v \<leftarrow> load_word_offs sb_ptr x;
                                       store_word_offs rb_ptr x v
                                     od)
               [length msg_registers + 1 ..< Suc (unat n)]
     | _ \<Rightarrow> return [];
     return $ min n $ nat_to_len $ length hardware_mrs + length buf_mrs
   od"

text {* The ctable and vtable slots of the TCB. *}
definition
  get_tcb_ctable_ptr :: "obj_ref \<Rightarrow> cslot_ptr" where
  "get_tcb_ctable_ptr tcb_ref \<equiv> (tcb_ref, tcb_cnode_index 0)"

definition
  get_tcb_vtable_ptr :: "obj_ref \<Rightarrow> cslot_ptr" where
  "get_tcb_vtable_ptr tcb_ref \<equiv> (tcb_ref, tcb_cnode_index 1)"

text {* Copy a set of registers from a thread to memory and vice versa. *}
definition
  copyRegsToArea :: "register list \<Rightarrow> obj_ref \<Rightarrow> obj_ref \<Rightarrow> (unit,'z::state_ext) s_monad" where
  "copyRegsToArea regs thread ptr \<equiv> do
     context \<leftarrow> thread_get tcb_context thread;
     zipWithM_x (store_word_offs ptr)
       [0 ..< length regs]
       (map context regs)
  od"

definition
  copyAreaToRegs :: "register list \<Rightarrow> obj_ref \<Rightarrow> obj_ref \<Rightarrow> (unit,'z::state_ext) s_monad" where
  "copyAreaToRegs regs ptr thread \<equiv> do
     old_regs \<leftarrow> thread_get tcb_context thread;
     vals \<leftarrow> mapM (load_word_offs ptr) [0 ..< length regs];
     vals2 \<leftarrow> return $ zip vals regs;
     vals3 \<leftarrow> return $ map (\<lambda>(v, r). (sanitiseRegister r v, r)) vals2;
     new_regs \<leftarrow> return $ foldl (\<lambda>rs (v, r). rs ( r := v )) old_regs vals3;
     thread_set (\<lambda>tcb. tcb \<lparr> tcb_context := new_regs \<rparr>) thread
   od"

text {* Optionally update the tcb at an address. *}
definition
  option_update_thread :: "obj_ref \<Rightarrow> ('a \<Rightarrow> tcb \<Rightarrow> tcb) \<Rightarrow> 'a option \<Rightarrow> (unit,'z::state_ext) s_monad" where
 "option_update_thread thread fn \<equiv> case_option (return ()) (\<lambda>v. thread_set (fn v) thread)"

text {* Check that a related capability is at an address. This is done before
calling @{const cap_insert} to avoid a corner case where the would-be parent of
the cap to be inserted has been moved or deleted. *}
definition
  check_cap_at :: "cap \<Rightarrow> cslot_ptr \<Rightarrow> (unit,'z::state_ext) s_monad \<Rightarrow> (unit,'z::state_ext) s_monad" where
 "check_cap_at cap slot m \<equiv> do
    cap' \<leftarrow> get_cap slot;
    when (same_object_as cap cap') m
  od"


text {* Helper function for binding async endpoints *}
definition
  bind_async_endpoint :: "32 word \<Rightarrow> 32 word \<Rightarrow> (unit,'z::state_ext) s_monad"
where
  "bind_async_endpoint tcbptr aepptr \<equiv> do
     aep \<leftarrow> get_async_ep aepptr;
     aep' \<leftarrow> return $ aep_set_bound_tcb aep (Some tcbptr);
     set_async_ep aepptr aep';
     set_bound_aep tcbptr $ Some aepptr
   od"

text {* TCB capabilities confer authority to perform seven actions. A thread can
request to yield its timeslice to another, to suspend or resume another, to
reconfigure another thread, or to copy register sets into, out of or between
other threads. *}
fun
  invoke_tcb :: "tcb_invocation \<Rightarrow> (data list,'z::state_ext) p_monad"
where
  "invoke_tcb (Suspend thread) = liftE (do suspend thread; return [] od)" 
| "invoke_tcb (Resume thread) = liftE (do restart thread; return [] od)"

| "invoke_tcb (ThreadControl target slot faultep priority croot vroot buffer)
   = doE
    liftE $ option_update_thread target (tcb_fault_handler_update o K) faultep;
    liftE $ case priority of None \<Rightarrow> return()
     | Some prio \<Rightarrow> do_extended_op (set_priority target prio);
    (case croot of None \<Rightarrow> returnOk ()
     | Some (new_cap, src_slot) \<Rightarrow> doE
      cap_delete (target, tcb_cnode_index 0);
      liftE $ check_cap_at new_cap src_slot
            $ check_cap_at (ThreadCap target) slot
            $ cap_insert new_cap src_slot (target, tcb_cnode_index 0)
    odE);
    (case vroot of None \<Rightarrow> returnOk ()
     | Some (new_cap, src_slot) \<Rightarrow> doE
      cap_delete (target, tcb_cnode_index 1);
      liftE $ check_cap_at new_cap src_slot
            $ check_cap_at (ThreadCap target) slot
            $ cap_insert new_cap src_slot (target, tcb_cnode_index 1)
    odE);
    (case buffer of None \<Rightarrow> returnOk ()
     | Some (ptr, frame) \<Rightarrow> doE
      cap_delete (target, tcb_cnode_index 4);
      liftE $ thread_set (\<lambda>t. t \<lparr> tcb_ipc_buffer := ptr \<rparr>) target;
      liftE $ case frame of None \<Rightarrow> return ()
       | Some (new_cap, src_slot) \<Rightarrow>
            check_cap_at new_cap src_slot
          $ check_cap_at (ThreadCap target) slot
          $ cap_insert new_cap src_slot (target, tcb_cnode_index 4)
    odE);
    returnOk []
  odE"

| "invoke_tcb (CopyRegisters dest src suspend_source resume_target transfer_frame transfer_integer transfer_arch) =  
  (liftE $ do
    when suspend_source $ suspend src;
    when resume_target $ restart dest;
    when transfer_frame $ do
        mapM_x (\<lambda>r. do
                v \<leftarrow> as_user src $ getRegister r;
                as_user dest $ setRegister r v
        od) frame_registers;
        pc \<leftarrow> as_user dest getRestartPC;
        as_user dest $ setNextPC pc
    od;
    when transfer_integer $ 
        mapM_x (\<lambda>r. do
                v \<leftarrow> as_user src $ getRegister r;
                as_user dest $ setRegister r v
        od) gpRegisters;
    return []
  od)"

| "invoke_tcb (ReadRegisters src suspend_source n arch) =
  (liftE $ do
    when suspend_source $ suspend src;
    self \<leftarrow> gets cur_thread;
    regs \<leftarrow> return (take (unat n) $ frame_registers @ gp_registers);
    as_user src $ mapM getRegister regs
  od)"

| "invoke_tcb (WriteRegisters dest resume_target values arch) =
  (liftE $ do
    self \<leftarrow> gets cur_thread;
    as_user dest $ do
        zipWithM (\<lambda>r v. setRegister r (sanitiseRegister r v))
            (frameRegisters @ gpRegisters) values;
        pc \<leftarrow> getRestartPC;
        setNextPC pc
    od;
    when resume_target $ restart dest;
    return []
  od)"

| "invoke_tcb (AsyncEndpointControl tcb (Some aepptr)) = 
  (liftE $ do
    bind_async_endpoint tcb aepptr;
    return []
  od)"

| "invoke_tcb (AsyncEndpointControl tcb None) =
  (liftE $ do
    unbind_async_endpoint tcb;
    return []
  od)"

definition
  set_domain :: "obj_ref \<Rightarrow> domain \<Rightarrow> unit det_ext_monad" where
  "set_domain tptr new_dom \<equiv> do
     cur \<leftarrow> gets cur_thread;
     tcb_sched_action tcb_sched_dequeue tptr;
     thread_set_domain tptr new_dom;
     ts \<leftarrow> get_thread_state tptr;
     when (runnable ts) (tcb_sched_action tcb_sched_enqueue tptr);
     when (tptr = cur) reschedule_required
   od"

definition invoke_domain:: "obj_ref \<Rightarrow> domain \<Rightarrow> (data list,'z::state_ext) p_monad"
where
  "invoke_domain thread domain \<equiv>
     liftE (do do_extended_op (set_domain thread domain); return [] od)" 

end
