with System;
with System.Storage_Elements;

--  Fixed-size, bounded allocation for the light embedded runtime. Allocating
--  and freeing an engine never calls malloc or grows a heap.
package WNM.Fixed_Pools is
   use System.Storage_Elements;
   type Pool (Bytes : Storage_Count; Capacity : Positive) is limited private;
   pragma Simple_Storage_Pool_Type (Pool);

   procedure Allocate (This : in out Pool;
                       Address : out System.Address;
                       Size_In_Storage_Elements, Alignment : Storage_Count);
   procedure Deallocate (This : in out Pool;
                         Address : System.Address;
                         Size_In_Storage_Elements, Alignment : Storage_Count);
   function Storage_Size (This : Pool) return Storage_Count;

private
   type Aligned_Storage_Array is new Storage_Array with Alignment => 8;
   type Used_Array is array (Positive range <>) of Boolean;
   type Pool (Bytes : Storage_Count; Capacity : Positive) is limited record
      Memory : Aligned_Storage_Array (1 .. Bytes);
      Used : Used_Array (1 .. Capacity) := (others => False);
   end record with Alignment => 8;
end WNM.Fixed_Pools;
