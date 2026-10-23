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

with WNM.UI;
with MIDI.Time;

package WNM.Project.Step_Sequencer is

   function Playing_Step (T : Tracks) return Playhead;

   procedure Play_Pause;
   --  Use it to signal a play/pause event

   procedure On_Press (Button : Keyboard_Button;
                       Mode : WNM.UI.Main_Modes);

   procedure MIDI_Clock_Tick (Step : MIDI.Time.Step_Count);

   function Keyboard_Octave return Octave_Offset;

   procedure Record_Note (Key : MIDI.MIDI_Key;
                          Velocity : MIDI.MIDI_Data;
                          Now : Time.Time_Microseconds := Time.Clock);
   --  Record at the playing track's current sixteenth-note cell. With
   --  quantize disabled, retain the onset at 1/128-cell resolution.
   --  While stopped, write the selected step. Monitor the note immediately.


private

   Current_Playing_Step : Sequencer_Steps := Sequencer_Steps'First with Atomic;

   --  Current_Seq_State : Sequencer_State := Pause with Atomic;
   Current_Track     : Tracks := Tracks'First with Atomic;

   procedure Execute_Step;

end WNM.Project.Step_Sequencer;
