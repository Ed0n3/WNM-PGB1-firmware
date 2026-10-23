with Ada.Text_IO;
with Ada.Exceptions;
with GNAT.OS_Lib;
with ASFML_SIM_Storage;
with WNM.File_System;
with WNM.Project.CFW_Tests;

procedure CFW_Tests is
begin
   --  Use a fresh in-memory image; never open the user's simulator ROM.
   ASFML_SIM_Storage.Switch_Storage_TOML :=
     new String'("../tests/empty-rom.toml");
   declare
      Result : constant String := ASFML_SIM_Storage.Create_ROM;
   begin
      if Result /= "" then
         raise Program_Error with Result;
      end if;
   end;
   WNM.File_System.Mount;
   WNM.Project.CFW_Tests.Run;
   Ada.Text_IO.Put_Line ("CFW regression tests passed");
   GNAT.OS_Lib.OS_Exit (0);
exception
   when E : others =>
      Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Information (E));
      GNAT.OS_Lib.OS_Exit (1);
end CFW_Tests;
