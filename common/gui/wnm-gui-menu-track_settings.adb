-------------------------------------------------------------------------------
--                                                                           --
--                              Wee Noise Maker                              --
--                                                                           --
--                  Copyright (C) 2016-2017 Fabien Chouteau                  --
--                                                                           --
--    Wee Noise Maker is free software: you can redistribute it and/or       --
--    modify it under the terms of the GNU General Public License as         --
--    published by the Free Software Foundation, either version 3 of the     --
--    License, or (at your option) any later version.                        --
--                                                                           --
--    Wee Noise Maker is distributed in the hope that it will be useful,     --
--    but WITHOUT ANY WARRANTY; without even the implied warranty of         --
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU       --
--    General Public License for more details.                               --
--                                                                           --
--    You should have received a copy of the GNU General Public License      --
--    along with We Noise Maker. If not, see <http://www.gnu.org/licenses/>. --
--                                                                           --
-------------------------------------------------------------------------------

with Interfaces;

with WNM.GUI.Menu.Drawing; use WNM.GUI.Menu.Drawing;
with WNM.GUI.Popup;
with WNM.GUI.Menu.Text_Dialog;
with WNM.Synth;

with WNM.Utils; use WNM.Utils;
with Tresses;

package body WNM.GUI.Menu.Track_Settings is

   use type Interfaces.Integer_8;

   Track_Settings_Singleton : aliased Track_Settings_Menu;

   Valid_Top_Settings : array (Track_Mode_Kind, Top_Settings) of
     Boolean := (others => (others => False));

   Top_Settings_Count_Cache : array (Track_Mode_Kind) of
     Interfaces.Integer_8 := (others => 0);

   Top_Settings_Position_Cache : array (Track_Mode_Kind, Top_Settings) of
     Interfaces.Integer_8 := (others => (others => -1));

   ------------
   -- To_Top --
   ------------

   function To_Top (S : Sub_Settings) return Top_Settings
   is (case S is
       when Project.Track_Mode => Track_Mode,
       when Project.Engine => Engine,
       when Project.Volume => Volume,
       when Project.Pan => Pan,
       when Project.Master_FX => Master_FX,
       when Project.Track_Octave_Offset => Octave_Offset,
       when Project.Shuffle => Shuffle,
       when Project.LFO_Rate => LFO,
       when Project.LFO_Amplitude => LFO,
       when Project.LFO_Shape => LFO,
       when Project.LFO_Target => LFO,
       when Project.LFO_Amp_Mode | Project.LFO_Loop | Project.LFO_Sync => LFO,
       when Project.Arp_Mode => Arp_Mode,
       when Project.Arp_Notes => Arp_Notes,
       when Project.Arp_Length => Arp_Length,
       when Project.Arp_Note => Arp_Note,
       when Project.Record_Quantize => Record_Quantize,
       when Project.Notes_Per_Chord => Notes_Per_Chord,
       when Project.MIDI_Chan => MIDI_Chan,
       when Project.MIDI_Instrument => MIDI_Instrument,
       when Project.CC_Default_A => CC_Default,
       when Project.CC_Default_B => CC_Default,
       when Project.CC_Default_C => CC_Default,
       when Project.CC_Default_D => CC_Default,
       when Project.CC_Ctrl_A => CC_Ctrl_A,
       when Project.CC_Label_A => CC_Label_A,
       when Project.CC_Ctrl_B => CC_Ctrl_B,
       when Project.CC_Label_B => CC_Label_B,
       when Project.CC_Ctrl_C => CC_Ctrl_C,
       when Project.CC_Label_C => CC_Label_C,
       when Project.CC_Ctrl_D => CC_Ctrl_D,
       when Project.CC_Label_D => CC_Label_D);

   -------------------------
   -- Fix_Current_Setting --
   -------------------------

   procedure Fix_Current_Setting (This : in out Track_Settings_Menu) is
   begin
      Editing_Arp_Note := Arp_Note_Index'Min
        (Editing_Arp_Note, Project.Arp_Length (Editing_Track));
      if This.Current_Setting = Project.Engine and then
        not Valid_Setting (Mode (Editing_Track), Project.Engine)
      then
         This.Current_Setting := CC_Default_A;
      end if;
      if not Valid_Setting (Mode (Editing_Track), This.Current_Setting) then
         Prev_Valid_Setting (Mode (Editing_Track), This.Current_Setting);
      end if;
      if not Valid_Setting (Mode (Editing_Track), This.Current_Setting) then
         Next_Valid_Setting (Mode (Editing_Track), This.Current_Setting);
      end if;
   end Fix_Current_Setting;

   ------------------------
   -- Top_Settings_Count --
   ------------------------

   function Top_Settings_Count (M : Project.Track_Mode_Kind) return Positive
   is
   begin
      --  Computed at elaboration
      return Positive (Top_Settings_Count_Cache (M));
   end Top_Settings_Count;

   --------------------------
   -- Top_Setting_Position --
   --------------------------

   function Top_Setting_Position (S : Top_Settings;
                                  M : Project.Track_Mode_Kind)
                                  return Natural
   is
   begin
      --  Computed at elaboration
      return Natural (Top_Settings_Position_Cache (M, S));
   end Top_Setting_Position;

   --  UI order is independent of the persisted Track_Settings enum IDs.
   type Settings_Order is array (Positive range 1 .. Sub_Settings'Pos
                                 (Sub_Settings'Last) + 1) of Sub_Settings;

   function UI_Order (M : Project.Track_Mode_Kind) return Settings_Order is
      Order : Settings_Order :=
        (Project.Engine, Project.Track_Mode,
         CC_Default_A, CC_Default_B, CC_Default_C, CC_Default_D,
         LFO_Rate, LFO_Amplitude, LFO_Shape, LFO_Target,
         Project.Volume, Project.Pan, Project.Master_FX,
         Track_Octave_Offset, Project.Shuffle,
         Project.Arp_Mode, Project.Arp_Notes, Project.Notes_Per_Chord,
         Project.MIDI_Chan, Project.MIDI_Instrument,
         Project.CC_Ctrl_A, Project.CC_Label_A,
         Project.CC_Ctrl_B, Project.CC_Label_B,
         Project.CC_Ctrl_C, Project.CC_Label_C,
         Project.CC_Ctrl_D, Project.CC_Label_D,
         LFO_Amp_Mode, LFO_Loop, LFO_Sync,
         Project.Arp_Length, Project.Arp_Note, Project.Record_Quantize);
   begin
      if not Valid_Setting (M, Project.Engine) then
         --  MIDI and FX have no engine page; their defaults page comes first.
         Order (1) := CC_Default_A;
         Order (2) := CC_Default_B;
         Order (3) := CC_Default_C;
         Order (4) := CC_Default_D;
         Order (5) := Project.Track_Mode;
         Order (6) := Project.Engine;
      end if;
      return Order;
   end UI_Order;

   ------------------------
   -- Next_Valid_Setting --
   ------------------------

   procedure Next_Valid_Setting (M : Project.Track_Mode_Kind;
                                 S : in out Sub_Settings)
   is
      Order : constant Settings_Order := UI_Order (M);
   begin
      for I in Order'Range loop
         if Order (I) = S then
            for J in I + 1 .. Order'Last loop
               if Valid_Setting (M, Order (J)) then
                  S := Order (J);
                  return;
               end if;
            end loop;
            return;
         end if;
      end loop;
   end Next_Valid_Setting;

   ------------------------
   -- Prev_Valid_Setting --
   ------------------------

   procedure Prev_Valid_Setting (M : Project.Track_Mode_Kind;
                                 S : in out Sub_Settings)
   is
      Order : constant Settings_Order := UI_Order (M);
   begin
      for I in Order'Range loop
         if Order (I) = S then
            for J in reverse Order'First .. I - 1 loop
               if Valid_Setting (M, Order (J)) then
                  S := Order (J);
                  return;
               end if;
            end loop;
            return;
         end if;
      end loop;
   end Prev_Valid_Setting;

   --------------
   -- To_CC_Id --
   --------------

   function To_CC_Id (S : Sub_Settings) return Project.CC_Id
   is (case S is
          when CC_Default_A | CC_Ctrl_A | CC_Label_A => A,
          when CC_Default_B | CC_Ctrl_B | CC_Label_B => B,
          when CC_Default_C | CC_Ctrl_C | CC_Label_C => C,
          when CC_Default_D | CC_Ctrl_D | CC_Label_D => D,
          when others => raise Program_Error);

   -----------------
   -- Push_Window --
   -----------------

   procedure Push_Window is
   begin
      Push (Track_Settings_Singleton'Access);
   end Push_Window;

   ----------
   -- Draw --
   ----------

   overriding
   procedure Draw
     (This : in out Track_Settings_Menu)
   is
      use Tresses;

      Mode : Project.Track_Mode_Kind;
      Sub : Sub_Settings;
      Top : Top_Settings;
      T : constant Tracks := Editing_Track;
   begin
      This.Fix_Current_Setting;

      Mode := Project.Mode (T);
      Sub := This.Current_Setting;
      Top := To_Top (This.Current_Setting);

      Draw_Menu_Box ("Track settings",
                     Count => Top_Settings_Count (Mode),
                     Index => Top_Setting_Position (Top, Mode));
      case Top is
         when Arp_Length =>
            Draw_Title ("Custom arp length:", "");
            Draw_Value (Project.Arp_Length (T)'Img);
         when Arp_Note =>
            Draw_Title ("Custom arp note" & Editing_Arp_Note'Img,
                        "A/B: select note");
            Draw_Value (Key_Img (Project.Arp_Note (T, Editing_Arp_Note)));
         when Record_Quantize =>
            Draw_Title ("Live record quantize:", "");
            Draw_Value (if Project.Record_Quantize (T) then "On" else "Off");
         when Track_Mode =>
            Draw_Title ("Track mode:", "");
            Draw_Value (Img (Mode));

         when Volume =>
            declare
               Value : constant Audio_Volume := Project.Track_Volume (T);
               Scaled : constant Param_Range :=
                 Param_Range (Value) *
                 (Param_Range'Last / Param_Range (Audio_Volume'Last));

               M : constant Project.Track_Mode_Kind := Project.Mode (T);
               Chan : constant MIDI.MIDI_Channel :=
                 Project.Voice_MIDI_Chan (T);
            begin
               Draw_Title ("Volume:", "");
               Draw_Str (Box_Center.X - 11, Value_Text_Y,
                        Value'Img & "%");
               if M in Project.Synth_Track_Mode_Kind then

                  Draw_LFO_Bar
                    (Box_Center.X,
                     Box_Center.Y,
                     Box_Width - 10,
                     Scaled,
                     WNM.Synth.Param_Value_After_LFO (Chan),
                     Draw_LFO => Project.LFO_Target (T) = Vol);
               end if;
            end;

         when Pan =>
            declare
               Value : constant Audio_Pan := Project.Track_Pan (T);
               Scaled : constant Param_Range :=
                 Param_Range (Value) *
                 (Param_Range'Last / Param_Range (Audio_Pan'Last));

               M : constant Project.Track_Mode_Kind := Project.Mode (T);
               Chan : constant MIDI.MIDI_Channel :=
                 Project.Voice_MIDI_Chan (T);
            begin
               Draw_Title ("Pan:", "");
               Draw_Str (Box_Center.X - 8, Value_Text_Y,
                        Value'Img);
               if M in Project.Synth_Track_Mode_Kind then

                  Draw_LFO_Bar
                    (Box_Center.X,
                     Box_Center.Y,
                     Box_Width - 10,
                     Scaled,
                     WNM.Synth.Param_Value_After_LFO (Chan),
                     Draw_LFO => Project.LFO_Target (T) = Pan,
                     Param_Start => Center);
               end if;
            end;

         when Master_FX =>
            Draw_Title ("FX send:", "");
            Draw_Value (Img (Project.Master_FX (T)));

            Draw_FX (Id => WNM.Project.A,
                     Value => Project.Master_FX (T),
                     Selected => False,
                     Label => "");

         when Octave_Offset =>
            Draw_Title ("Octave offset:", "");
            Draw_Value (Project.Track_Offset (T)'Img);

         when Shuffle =>
            Draw_Title ("Shuffle:", "");
            declare
               Shuffle : constant Project.Shuffle_Value :=
                 Project.Track_Shuffle (T);

               Linn : constant Integer :=
                 50 + Integer (Shuffle) / 2;

               Str : constant String :=
                 Linn'Img & (if Shuffle mod 2 = 1 then ".5" else ".0");
            begin
               Draw_Value (Str);
            end;

         when Arp_Mode =>
            Draw_Title ("Arpeggiator mode:", "");
            Draw_Value (Project.Img (Project.Arp_Mode (T)));

         when Arp_Notes =>
            Draw_Title ("Arpeggiator notes:", "");
            Draw_Value (Project.Img (Project.Arp_Notes (T)));

         when Notes_Per_Chord =>
            Draw_Title ("Notes per Chord:", "");
            Draw_Value (Project.Notes_Per_Chord (T)'Img);

         when MIDI_Chan =>
            Draw_Title ("MIDI Channel:", "");
            Draw_Value (Natural'Image (Natural (Project.MIDI_Chan (T)) + 1));

         when MIDI_Instrument =>
            Draw_Title ("MIDI instrument:", "");
            Draw_Value (Builtin_Instruments (This.Instrument).Name);

         when Engine =>
            declare
               Count : constant Natural := Project.Engines_Count (T);
               Current : constant Natural :=
                 Natural (Project.Selected_Engine (T)) + 1;

            begin
               Draw_Title ("Synth Engine: " &
                             Trim (Current'Img) & "/" &
                             Trim (Count'Img),
                           "");
               Draw_Fit_Screen (Box_Left + 8,
                                Value_Text_Y - Font_Height - 1,
                                Project.Selected_Engine_Img (T));
            end;

         when LFO =>

            case Sub is
               when LFO_Rate =>
                  Draw_Title ("LFO Rate:", "");
               when LFO_Amplitude =>
                  Draw_Title ("LFO Amp: " &
                                Project.Img (Project.LFO_Amp_Mode (T)),
                              "");
               when LFO_Shape =>
                  Draw_Title ("LFO Shape: " &
                                Project.Img (Project.LFO_Shape (T)),
                              "");
               when LFO_Target =>
                  Draw_Title ("LFO Target:", "");
               when others =>
                  null;
            end case;

            Draw_CC_Value
              (A,
               Project.LFO_Rate (T),
               "RAT",
               Sub = LFO_Rate);

            Draw_CC_Value
              (B,
               Project.LFO_Amp (T),
               "AMP",
               Sub = LFO_Amplitude,
               Style => (case LFO_Amp_Mode (T) is
                            when Project.Positive => Drawing.Positive,
                            when Project.Center   => Drawing.Center,
                            when Project.Negative => Drawing.Negative));

            Draw_LFO_Shape (C,
                            "SHP",
                            Sub = LFO_Shape,
                            Project.LFO_Shape (T),
                            Project.LFO_Sync (T),
                            Project.LFO_Loop (T));

            Draw_CC_Value
              (D,
               0,
               Project.LFO_Target (T)'Img,
               Sub = LFO_Target);

            declare
               M : constant Project.Track_Mode_Kind := Project.Mode (T);
               Chan : constant MIDI.MIDI_Channel :=
                 Project.Voice_MIDI_Chan (T);
            begin
               if M in Project.Synth_Track_Mode_Kind
                 and then
                   Project.LFO_Target (T) /= None
               then
                  Draw_LFO_Bar (Box_Center.X,
                                Box_Top + Font_Height + 6,
                                Box_Width - 10,
                                WNM.Synth.Param_Value_Before_LFO (Chan),
                                WNM.Synth.Param_Value_After_LFO (Chan),
                                Draw_LFO => True);
               end if;
            end;

         when CC_Default =>
            declare
               LFO_Value : MIDI.MIDI_Data := 0;
               LFO_Target : LFO_Target_Kind := None;
            begin
               if Mode /= MIDI_Mode then
                  LFO_Target := Project.LFO_Target (T);
                  LFO_Value := Tresses.Param_MIDI
                    (WNM.Synth.Param_Value_After_LFO
                       (Project.Voice_MIDI_Chan (T)));
               end if;

               Draw_CC_Control_Page
                 (T => T,
                  Selected => To_CC_Id (Sub),
                  Val_A => Project.CC_Default (T, A),
                  Val_B => Project.CC_Default (T, B),
                  Val_C => Project.CC_Default (T, C),
                  Val_D => Project.CC_Default (T, D),
                  Ena_A => True,
                  Ena_B => True,
                  Ena_C => True,
                  Ena_D => True,
                  LFO_Target => LFO_Target,
                  LFO_Value  => LFO_Value);
            end;

         when CC_Ctrl_A | CC_Ctrl_B | CC_Ctrl_C | CC_Ctrl_D =>
            declare
               CC : constant Project.CC_Id := To_CC_Id (Sub);
            begin
               Draw_Title ("MIDI CC " & Project.CC_Letter (CC) & ":", "");
               Draw_Value ("Controller:" &
                             Project.CC_Controller (T, CC)'Img);
            end;

         when CC_Label_A | CC_Label_B | CC_Label_C | CC_Label_D =>
            declare
               CC : constant Project.CC_Id := To_CC_Id (Sub);
            begin
               Draw_Title ("MIDI CC " & Project.CC_Letter (CC) & " Label:",
                           "");
               Draw_Value (Project.CC_Controller_Label (T, CC));
            end;

      end case;

   end Draw;

   --------------
   -- On_Event --
   --------------

   overriding
   procedure On_Event
     (This  : in out Track_Settings_Menu;
      Event : Menu_Event)
   is
      T : constant Tracks := Editing_Track;
   begin
      if This.Current_Setting = Project.Arp_Note then
         if Event.Kind = A_Press then
            Editing_Arp_Note := Editing_Arp_Note mod Project.Arp_Length (Editing_Track) + 1;
            return;
         elsif Event.Kind = B_Press then
            Editing_Arp_Note := (if Editing_Arp_Note <= 1 then
                                  Project.Arp_Length (Editing_Track)
                                else Editing_Arp_Note - 1);
            return;
         end if;
      end if;

      This.Fix_Current_Setting;

      case Event.Kind is
         when Left_Press =>
            Prev_Valid_Setting (Mode (T),
                                This.Current_Setting);
         when Right_Press =>
            Next_Valid_Setting (Mode (T),
                                This.Current_Setting);

         when Up_Press =>
            case This.Current_Setting is
               when MIDI_Instrument =>
                     if This.Instrument < Builtin_Instruments'Last then
                        This.Instrument := This.Instrument + 1;
                     end if;
               when CC_Label_A | CC_Label_B | CC_Label_C | CC_Label_D =>
                  GUI.Popup.Display ("Press A to edit ", 500_000);

               when others =>
                  Project.Next_Value (T, This.Current_Setting);
                  --  Project.Next_Value_Fast (This.Current_Setting);
            end case;
         when Down_Press =>
            case This.Current_Setting is
               when MIDI_Instrument =>
                  if This.Instrument > Builtin_Instruments'First then
                     This.Instrument := This.Instrument - 1;
                  end if;

               when CC_Label_A | CC_Label_B | CC_Label_C | CC_Label_D =>
                  GUI.Popup.Display ("Press A to edit ", 500_000);

               when others =>
                  Project.Prev_Value (T, This.Current_Setting);
                  --  Project.Prev_Value_Fast (This.Current_Setting);
            end case;

         when A_Press =>
            case This.Current_Setting is
               when MIDI_Instrument =>

                  --  Apply selected instrument settings
                  declare
                     I : MIDI_Instrument_Settings renames
                       Builtin_Instruments (This.Instrument);
                  begin
                     Set_CC_Controller (T, A, I.CC_Target_A);
                     Set_CC_Controller (T, B, I.CC_Target_B);
                     Set_CC_Controller (T, C, I.CC_Target_C);
                     Set_CC_Controller (T, D, I.CC_Target_D);

                     Set_CC_Controller_Label (T, A, I.CC_A_Label);
                     Set_CC_Controller_Label (T, B, I.CC_B_Label);
                     Set_CC_Controller_Label (T, C, I.CC_C_Label);
                     Set_CC_Controller_Label (T, D, I.CC_D_Label);
                  end;

               when CC_Label_A | CC_Label_B | CC_Label_C | CC_Label_D =>

                  --  Push text edit dialog

                  declare
                     CC : constant Project.CC_Id :=
                       To_CC_Id (This.Current_Setting);
                  begin
                     WNM.GUI.Menu.Text_Dialog.Set_Title
                       ("CC " & Project.CC_Letter (CC) & " Label");
                     WNM.GUI.Menu.Text_Dialog.Push_Window
                       (Utils.Trim
                          (Project.CC_Controller_Label (T, CC)));
                  end;

               when LFO_Amplitude =>
                  Project.LFO_Amp_Mode_Next (T);

               when LFO_Shape =>
                  Project.LFO_Toggle_Loop (T);

               when others =>
                  null;
            end case;
         when B_Press =>
            case This.Current_Setting is
               when LFO_Shape =>
                  Project.LFO_Toggle_Sync (T);
               when LFO_Amplitude =>
                  Project.LFO_Amp_Mode_Prev (T);

               when others =>
                  null;
            end case;

         when Slider_Touch =>
            Project.Set (T,
                         This.Current_Setting,
                         Event.Slider_Value);
      end case;
   end On_Event;

   ---------------
   -- On_Pushed --
   ---------------

   overriding
   procedure On_Pushed
     (This  : in out Track_Settings_Menu)
   is
   begin
      null;
   end On_Pushed;

   --------------
   -- On_Focus --
   --------------

   overriding
   procedure On_Focus
     (This       : in out Track_Settings_Menu;
      Exit_Value : Window_Exit_Value)
   is
      Sub : Sub_Settings;
      T : constant Tracks := Editing_Track;
   begin
      This.Fix_Current_Setting;

      Sub := This.Current_Setting;

      if Sub in CC_Label_A | CC_Label_B | CC_Label_C | CC_Label_D
      then

         --  Return from controller label text edit

         if Exit_Value = Success then
            declare
               CC : constant CC_Id := To_CC_Id (Sub);
               Output : constant String := WNM.GUI.Menu.Text_Dialog.Value;
               Label : Controller_Label := Empty_Controller_Label;
            begin
               Utils.Copy_Str (Output, Label);
               Project.Set_CC_Controller_Label (T, CC, Label);
            end;
         end if;
      end if;
   end On_Focus;

begin

   for Mode in Project.Track_Mode_Kind loop

      for Sub in Sub_Settings loop
         if Valid_Setting (Mode, Sub) then
            Valid_Top_Settings (Mode, To_Top (Sub)) := True;
         end if;
      end loop;

      --  I don't think there is a way to know the number of settings per
      --  mode at compile time because it depends on the results of the
      --  Valid_Setting function. So we compute the numbers here and cache
      --  the result for futre calls.

      for Top in Top_Settings loop
         if Valid_Top_Settings (Mode, Top) then
            Top_Settings_Count_Cache (Mode) :=
              Top_Settings_Count_Cache (Mode) + 1;
         end if;
      end loop;

      --  Same as Settings_Count, we compute the numbers here and cache the
      --  result for futre calls.

      declare
         Cnt : Interfaces.Integer_8 := 0;
         Seen : array (Top_Settings) of Boolean := (others => False);
      begin
         for Sub of UI_Order (Mode) loop
            if Valid_Setting (Mode, Sub) and then not Seen (To_Top (Sub)) then
               Top_Settings_Position_Cache (Mode, To_Top (Sub)) := Cnt;
               Seen (To_Top (Sub)) := True;
               Cnt := Cnt + 1;
            end if;
         end loop;
      end;

   end loop;
end WNM.GUI.Menu.Track_Settings;
