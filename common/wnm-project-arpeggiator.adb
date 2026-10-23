-------------------------------------------------------------------------------
--                                                                           --
--                              Wee Noise Maker                              --
--                                                                           --
--                     Copyright (C) 2022 Fabien Chouteau                    --
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

with WNM.Chord_Settings;
with WNM.Project.Chord_Sequencer;

package body WNM.Project.Arpeggiator is

   type Arp_Pattern is array (Natural range <>) of
     WNM.Chord_Settings.Chord_Index_Range;
   type Arp_Pattern_Acc is not null access constant Arp_Pattern;

   Arp_Up : aliased constant Arp_Pattern :=
     (0, 1, 2, 3);

   pragma Compile_Time_Error
     (Arp_Up'Length /= WNM.Chord_Settings.Chord_Notes'Length,
      "Number of notes in chords changed");

   Arp_Down : aliased constant Arp_Pattern :=
     (3, 2, 1, 0);

   pragma Compile_Time_Error
     (Arp_Down'Length /= WNM.Chord_Settings.Chord_Notes'Length,
      "Number of notes in chords changed");

   Arp_Up_Down : aliased constant Arp_Pattern :=
     (0, 1, 2, 3, 2, 1);

   pragma Compile_Time_Error
     (Arp_Up_Down'Length /= (2 * WNM.Chord_Settings.Chord_Notes'Length) - 2,
      "Number of notes in chords changed");

   Arp_Pat1 : aliased constant Arp_Pattern :=
     (0, 3, 2, 3, 1, 3, 2, 3);

   Arp_Pat2 : aliased constant Arp_Pattern :=
     (0, 1, 2, 3, 1, 3, 2, 3);

   Arp_Pat3 : aliased constant Arp_Pattern :=
     (0, 2, 1, 3, 2, 1, 2);

   ---------------
   -- Next_Note --
   ---------------

   function Next_Note (T : Tracks) return MIDI.MIDI_Key is
      use WNM.Chord_Settings;
      use WNM.Project.Chord_Sequencer;

      Track : Track_Rec renames G_Project.Tracks (T);
      Arp : Arpeggiator_Rec renames Arpeggiators (T);

      Count : constant Standard.Positive :=
        (if Track.Arp_Notes = Custom then Track.Arp_Length
         else Chord_Notes'Length);
      Index : Natural;
      Position : Natural;
   begin
      case Track.Arp_Mode is
         when Random =>
            Index := Natural (WNM.Random) mod Count;
         when Up =>
            Index := Arp.Next_Index mod Count;
         when Down =>
            Index := Count - 1 - Arp.Next_Index mod Count;
         when Up_Down =>
            if Count = 1 then
               Index := 0;
            else
               Position := Arp.Next_Index mod (2 * Count - 2);
               Index := (if Position < Count then Position
                         else 2 * Count - 2 - Position);
            end if;
         when Pattern1 | Pattern2 | Pattern3 =>
            declare
               Pat : constant Arp_Pattern_Acc :=
                 (case Track.Arp_Mode is
                    when Pattern1 => Arp_Pat1'Access,
                    when Pattern2 => Arp_Pat2'Access,
                    when others => Arp_Pat3'Access);
            begin
               Index := Natural (Pat (Arp.Next_Index mod Pat'Length)) mod Count;
            end;
      end case;
      --  Keep the counter bounded during indefinitely looping performances.
      declare
         Cycle : constant Standard.Positive :=
           (case Track.Arp_Mode is
              when Up | Down | Random => Count,
              when Up_Down => (if Count = 1 then 1 else 2 * Count - 2),
              when Pattern1 | Pattern2 => 8,
              when Pattern3 => 7);
      begin
         Arp.Next_Index := (Arp.Next_Index + 1) mod Cycle;
      end;
      return (if Track.Arp_Notes = Custom
              then Track.Arp_Keys (Index + 1)
              else Current_Chord (Chord_Index_Range (Index)));
   end Next_Note;

   -----------------------------
   -- Signal_Start_Of_Pattern --
   -----------------------------

   procedure Signal_Start_Of_Pattern (T : Tracks) is
   begin

      --  Reset arp before the start of next pattern
      Arpeggiators (T).Next_Index := 0;
   end Signal_Start_Of_Pattern;

end WNM.Project.Arpeggiator;
