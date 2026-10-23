with Ada.Text_IO;
with WNM.Tasks;
with WNM.Synth;
with WNM.Screen;

package body WNM.GUI.Menu.Track_Settings.CFW_Tests is
   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Run is
      View : Track_Settings_Menu;
      Page, Previous_Page : Natural;
   begin
      Project.Editing_Track := Tracks'First;
      for Choice in 0 .. 10 loop
         if Choice <= 7 then
            Project.Editing_Track := Tracks'First;
            Project.Set (Tracks'First, Project.Track_Mode,
                         WNM_HAL.Touch_Value (Float (Choice) / 7.0));
         else
            --  The three FX modes are available only on reserved tracks 9-11.
            Project.Editing_Track := Tracks (Choice + 1);
            Project.Set (Project.Editing_Track, Project.Track_Mode, 0.0);
         end if;
         WNM.Tasks.Synth_Coproc_Receive;
         WNM.Synth.Process_Coproc_Events;
         declare
            M : constant Project.Track_Mode_Kind :=
              Project.Mode (Project.Editing_Track);
         begin
            View.Current_Setting := Project.Engine;
            Fix_Current_Setting (View);
            Check (Top_Setting_Position (To_Top (View.Current_Setting), M) = 0,
                   "initial track settings page is first");
            for I in 1 .. 4 loop
               On_Event (View, (Kind => Right_Press));
               exit when View.Current_Setting = Project.Track_Mode;
            end loop;
            Check (View.Current_Setting = Project.Track_Mode and then
                   Top_Setting_Position (Track_Mode, M) = 1,
                   "Track Mode must be page 2 for every instrument family");
            WNM.Screen.Clear;
            Draw (View);
            On_Event (View, (Kind => Left_Press));
            Check (Top_Setting_Position (To_Top (View.Current_Setting), M) = 0,
                   "left from Track Mode returns to page 1");
            On_Event (View, (Kind => Right_Press));
            Check (View.Current_Setting = Project.Track_Mode,
                   "right from page 1 returns to Track Mode");
            Previous_Page := 1;
            for I in 1 .. Sub_Settings'Pos (Sub_Settings'Last) + 1 loop
               On_Event (View, (Kind => Right_Press));
               Page := Top_Setting_Position (To_Top (View.Current_Setting), M);
               Check (Page in Previous_Page .. Previous_Page + 1,
                      "page indicators follow forward UI navigation");
               Previous_Page := Page;
               Draw (View);
            end loop;
            for I in 1 .. Sub_Settings'Pos (Sub_Settings'Last) + 1 loop
               On_Event (View, (Kind => Left_Press));
               Page := Top_Setting_Position (To_Top (View.Current_Setting), M);
               Check (Page <= Previous_Page and then Previous_Page - Page <= 1,
                      "page indicators follow backward UI navigation");
               Previous_Page := Page;
            end loop;
            Check (Previous_Page = 0, "left reaches the first settings page");
         end;
      end loop;
      Ada.Text_IO.Put_Line ("Track Mode page 2 checked for all 11 modes");
   end Run;
end WNM.GUI.Menu.Track_Settings.CFW_Tests;
