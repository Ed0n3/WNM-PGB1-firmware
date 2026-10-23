--  Synchronous coprocessor transport for regression tests. The production
--  interrupt task is deliberately absent: tests explicitly pump both queues.
with WNM_HAL; use WNM_HAL;

package body ASFML_Sim.Coproc_Queues is
   type Data_Array is array (Positive range 1 .. Coproc_Queue_Capacity)
     of Coproc_Data;
   type FIFO is record
      Data : Data_Array;
      First : Positive := 1;
      Last : Positive := 1;
      Count : Natural := 0;
   end record;
   Queues : array (Coproc_Target) of FIFO;

   procedure Push (Target : Coproc_Target; D : Coproc_Data) is
      Q : FIFO renames Queues (Target);
   begin
      if Q.Count = Coproc_Queue_Capacity then
         raise Program_Error with "Test coprocessor queue overflow";
      end if;
      Q.Data (Q.Last) := D;
      Q.Last := Q.Last mod Coproc_Queue_Capacity + 1;
      Q.Count := Q.Count + 1;
   end Push;

   procedure Pop (Target : Coproc_Target;
                  D : out Coproc_Data;
                  Success : out Boolean)
   is
      Q : FIFO renames Queues (Target);
   begin
      Success := Q.Count /= 0;
      if Success then
         D := Q.Data (Q.First);
         Q.First := Q.First mod Coproc_Queue_Capacity + 1;
         Q.Count := Q.Count - 1;
      end if;
   end Pop;
end ASFML_Sim.Coproc_Queues;
