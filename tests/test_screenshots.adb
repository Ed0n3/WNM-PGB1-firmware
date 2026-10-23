with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO;
with ASFML_Sim;
with WNM.Screen;

package body Test_Screenshots is
   procedure Save (Name : String) is
      use Ada.Streams;
      Directory : constant String :=
        Ada.Environment_Variables.Value ("CFW_SCREENSHOT_DIR", "");
      File : Stream_IO.File_Type;
      Pixels : Stream_Element_Array
        (1 .. Stream_Element_Offset (ASFML_Sim.Frame_Buffer'Length));
   begin
      if Directory = "" then
         return;
      end if;
      Ada.Directories.Create_Path (Directory);
      WNM.Screen.Update;
      for I in Pixels'Range loop
         Pixels (I) := Stream_Element (ASFML_Sim.Frame_Buffer (Integer (I) - 1));
      end loop;
      Stream_IO.Create (File, Stream_IO.Out_File,
                        Directory & "/" & Name & ".rgba");
      Stream_IO.Write (File, Pixels);
      Stream_IO.Close (File);
   end Save;
end Test_Screenshots;
