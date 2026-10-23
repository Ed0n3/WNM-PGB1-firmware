package body WNM.Fixed_Pools is
   procedure Allocate (This : in out Pool;
                       Address : out System.Address;
                       Size_In_Storage_Elements, Alignment : Storage_Count)
   is
      Stride : constant Storage_Count := This.Bytes / Storage_Count (This.Capacity);
   begin
      if Size_In_Storage_Elements > Stride or else Alignment > 8 then
         raise Storage_Error;
      end if;
      for I in This.Used'Range loop
         if not This.Used (I) then
            This.Used (I) := True;
            Address := This.Memory (Storage_Offset (I - 1) * Stride + 1)'Address;
            return;
         end if;
      end loop;
      raise Storage_Error;
   end Allocate;

   procedure Deallocate (This : in out Pool;
                         Address : System.Address;
                         Size_In_Storage_Elements, Alignment : Storage_Count)
   is
      pragma Unreferenced (Size_In_Storage_Elements, Alignment);
      Stride : constant Storage_Count := This.Bytes / Storage_Count (This.Capacity);
      I : constant Positive := Positive
        ((To_Integer (Address) - To_Integer (This.Memory'Address)) /
           Integer_Address (Stride) + 1);
   begin
      This.Used (I) := False;
   end Deallocate;

   function Storage_Size (This : Pool) return Storage_Count
   is (This.Memory'Length);
end WNM.Fixed_Pools;
