with WNM.Fixed_Pools;
with System.Storage_Elements;
with Ada.Unchecked_Deallocation;
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

with HAL; use HAL;

with WNM.Mixer;
with WNM.Voices.Snare_Voice;
with WNM.Voices.Sampler_Voice;
with WNM.Voices.Chord_Voice;
with WNM.Voices.Hihat_Voice;
with WNM.Voices.Kick_Voice;

with Tresses; use Tresses;
with Tresses.Voices.Macro;
with Tresses.Macro;
with Tresses.Interfaces;

with WNM.Generic_Queue;
with WNM.Utils;

with WNM.Shared_Buffers;

package body WNM.Synth is

   use type MIDI.MIDI_UInt8;

   subtype Voice_Slot is Positive range 1 .. Internal_Voice_Count;
   type Macro_Buffer_Array is array (Voice_Slot) of
     aliased Tresses.Voices.Macro.Macro_Buffers;
   Macro_Buffers : Macro_Buffer_Array
     with Import, Address => Shared_Buffers.Shared_Buffer
       (Shared_Buffers.Voice_Buffer_Offset)'Address;

   pragma Compile_Time_Error
     (Tresses.Voices.Macro.Macro_Buffers'Size >
        Shared_Buffers.Voice_Buffer_Byte_Size * 8,
      "Synth voice buffer exceeds its shared-memory slot");
   --  The array uses the actual component stride, bounded above by the slot
   --  reservation. No heap allocation occurs on either audio core.
   type Slot_Rec (B : access Tresses.Voices.Macro.Macro_Buffers;
                  Kind : Voice_Kind) is record
      case Kind is
         when Kick_Mode => TK : aliased WNM.Voices.Kick_Voice.Instance;
         when Snare_Mode => TS : aliased WNM.Voices.Snare_Voice.Instance;
         when Hihat_Mode => HH : aliased WNM.Voices.Hihat_Voice.Instance;
         when Chord_Mode => Chord : aliased WNM.Voices.Chord_Voice.Instance;
         when Sample1_Mode | Sample2_Mode =>
            Sampler : aliased WNM.Voices.Sampler_Voice.Instance;
         when Bass_Mode | Lead_Mode => Lead : aliased Tresses.Voices.Macro.Instance (B);
         when others => null;
      end case;
   end record;
   --  A fixed storage pool holds eight constrained variant records. This
   --  avoids both a general-purpose heap and storage for inactive engines.
   use System.Storage_Elements;
   Slot_Stride : constant Storage_Count := ((Slot_Rec'Max_Size_In_Storage_Elements + 7) / 8) * 8;
   Voice_Pool : WNM.Fixed_Pools.Pool
     (Slot_Stride * Internal_Voice_Count, Internal_Voice_Count);
   type Slot_Access is access Slot_Rec;
   for Slot_Access'Simple_Storage_Pool use Voice_Pool;
   procedure Free is new Ada.Unchecked_Deallocation (Slot_Rec, Slot_Access);
   Slots : array (Voice_Slot) of Slot_Access := (others => null);

   subtype Sample_Kind is Voice_Kind range Sample1_Mode .. Sample2_Mode;
   subtype Macro_Kind is Voice_Kind range Bass_Mode .. Lead_Mode;
   --  Ages are a permutation; touching a slot moves it to the back of the
   --  least-recently-played queue without a wrapping timestamp.
   Ages : array (Voice_Slot) of Natural := (others => 0);
   Owners : array (Voice_Slot) of Integer := (others => -1);
   Channel_Slot : array (Tresses_Channels) of Natural := (others => 0);
   Kinds : array (Tresses_Channels) of Voice_Kind := (others => MIDI_Mode);
   Engines : array (Tresses_Channels) of MIDI.MIDI_Data := (others => 0);

   Sample_Rec_Playback :
   WNM.Voices.Sampler_Voice.Sample_Rec_Playback_Instance;
   --  This voice is only used when playing the freshly recorded sample from
   --  RAM.

   subtype Voice_Class is Tresses.Interfaces.Four_Params_Voice'Class;


   subtype Lead_Engine_Range is MIDI.MIDI_Data range 0 .. 32;
   function Lead_Engines (V : MIDI.MIDI_Data) return Tresses.Synth_Engines
   is (case V is
          when 0  => Tresses.Voice_Saw_Swarm,
          when 1  => Tresses.Voice_Analog_Buzz,
          when 2  => Tresses.Voice_Analog_Morph,
          when 3  => Tresses.Voice_FM2OP,
          when 4  => Tresses.Voice_Sand,
          when 5  => Tresses.Voice_Bass_808,
          when 6  => Tresses.Voice_House_Bass,
          when 7  => Tresses.Voice_Pluck_Bass,
          when 8  => Tresses.Voice_Reese,
          when 9  => Tresses.Voice_Screech,
          when 10 => Tresses.Voice_Plucked,
          when 11 => Tresses.Voice_PDR_Sine,
          when 12 => Tresses.Voice_PDR_Triangle,
          when 13 => Tresses.Voice_PDR_Sine_Square,
          when 14 => Tresses.Voice_PDR_Square_Sine,
          when 15 => Tresses.Voice_PDL_Trig_Warp,
          when 16 => Tresses.Voice_PDL_Triangle_Screech,
          when 17 => Tresses.Voice_Chip_Glide,
          when 18 => Tresses.Voice_Chip_Phaser,
          when 19 => Tresses.Voice_Chip_Echo_Square,
          when 20 => Tresses.Voice_Chip_Echo_Square_Saw,
          when 21 => Tresses.Voice_Chip_Bass,
          when 22 => Tresses.Voice_PDR_Square_Full_Sine,
          when 23 => Tresses.Voice_Triangle_Phaser,
          when 24 => Tresses.Voice_Sine_Phaser,
          when 25 => Tresses.Voice_Sine_Pluck,
          when 26 => Tresses.Voice_Triangle_Pluck,
          when 27 => Tresses.Voice_Chip_Pluck,
          when 28 => Tresses.Voice_User_Wave_Glide,
          when 29 => Tresses.Voice_User_Wave_Phaser,
          when 30 => Tresses.Voice_User_Wave_Pluck,
          when 31 => Tresses.Voice_User_Wave_Echo,
          when 32 => Tresses.Voice_User_Wave_PDR,
          when Lead_Engine_Range'Last + 1 .. MIDI.MIDI_Data'Last
                  => Tresses.Synth_Engines'Last);

   subtype Kick_Engine_Range is MIDI.MIDI_Data range 0 .. 5;
   function Kick_Engines (V : MIDI.MIDI_Data)
                          return Voices.Kick_Voice.Kick_Engine
   is (case V is
          when 0 => Voices.Kick_Voice.Sine_Kick,
          when 1 => Voices.Kick_Voice.Triangle_Kick,
          when 2 => Voices.Kick_Voice.Chip_Kick,
          when 3 => Voices.Kick_Voice.Sine_Click_Kick,
          when 4 => Voices.Kick_Voice.User_Wave_Kick,
          when others => Voices.Kick_Voice.User_Wave_Click_Kick);

   subtype Snare_Engine_Range is MIDI.MIDI_Data range 0 .. 6;
   function Snare_Engines (V : MIDI.MIDI_Data)
                           return Voices.Snare_Voice.Snare_Engine
   is (case V is
          when 0 => Voices.Snare_Voice.Sine_Snare,
          when 1 => Voices.Snare_Voice.Saw_Snare,
          when 2 => Voices.Snare_Voice.Triangle_Snare,
          when 3 => Voices.Snare_Voice.Virt_Analog,
          when 4 => Voices.Snare_Voice.Clap,
          when 5 => Voices.Snare_Voice.Clap_HP,
          when others => Voices.Snare_Voice.User_Wave_Snare);

   subtype HH_Engine_Range is MIDI.MIDI_Data range 0 .. 24;
   function HH_Engines (V : MIDI.MIDI_Data)
                        return Voices.Hihat_Voice.HH_Engine
   is (case V is
          when 0 => Voices.Hihat_Voice.Cymbal,
          when 1 => Voices.Hihat_Voice.HH909,
          when 2 => Voices.Hihat_Voice.HH707,
          when 3 => Voices.Hihat_Voice.HH808,
          when 4 => Voices.Hihat_Voice.HH505,
          when 5 => Voices.Hihat_Voice.HHLM2,
          when 6 => Voices.Hihat_Voice.HHCR78,
          when 7 => Voices.Hihat_Voice.HHMRK2,
          when 8 => Voices.Hihat_Voice.HH_Acoustic,

          when 9 => Voices.Hihat_Voice.HH909_BP,
          when 10 => Voices.Hihat_Voice.HH707_BP,
          when 11 => Voices.Hihat_Voice.HH808_BP,
          when 12 => Voices.Hihat_Voice.HH505_BP,
          when 13 => Voices.Hihat_Voice.HHLM2_BP,
          when 14 => Voices.Hihat_Voice.HHCR78_BP,
          when 15 => Voices.Hihat_Voice.HHMRK2_BP,
          when 16 => Voices.Hihat_Voice.HH_Acoustic_BP,

          when 17 => Voices.Hihat_Voice.HH909_HP,
          when 18 => Voices.Hihat_Voice.HH707_HP,
          when 19 => Voices.Hihat_Voice.HH808_HP,
          when 20 => Voices.Hihat_Voice.HH505_HP,
          when 21 => Voices.Hihat_Voice.HHLM2_HP,
          when 22 => Voices.Hihat_Voice.HHCR78_HP,
          when 23 => Voices.Hihat_Voice.HHMRK2_HP,
          when 24 => Voices.Hihat_Voice.HH_Acoustic_HP,

          when others => Voices.Hihat_Voice.HH_Acoustic_HP);

   subtype Sampler_Engine_Range is MIDI.MIDI_Data range 0 .. 7;
   function Sampler_Engines (V : MIDI.MIDI_Data)
                        return Voices.Sampler_Voice.Sampler_Engine
   is (case V is
          when 0      => Voices.Sampler_Voice.Overdrive,
          when 1      => Voices.Sampler_Voice.Crusher,
          when 2      => Voices.Sampler_Voice.Glide_Fast,
          when 3      => Voices.Sampler_Voice.Glide_Slow,
          when 4      => Voices.Sampler_Voice.Pitch_Down_1oct,
          when 5      => Voices.Sampler_Voice.Pitch_Down_2oct,
          when 6      => Voices.Sampler_Voice.Pitch_Up_1oct,
          when 7      => Voices.Sampler_Voice.Pitch_Up_2oct,
          when others => Voices.Sampler_Voice.Crusher);

   subtype Chord_Engine_Range is MIDI.MIDI_Data range 0 .. 2;
   function Chord_Engines (V : MIDI.MIDI_Data)
                        return Voices.Chord_Voice.Chord_Engine
   is (case V is
          when 0      => Voices.Chord_Voice.Waveform,
          when 1      => Voices.Chord_Voice.Mixed_Waveforms,
          when others => Voices.Chord_Voice.Custom_Waveform);



   LFO_Targets : array (Tresses_Channels) of MIDI.MIDI_Data :=
     (others => Voice_Pan_CC);
     --  (others => MIDI.MIDI_Data'Last);

   LFOs       : array (Tresses_Channels) of Tresses.LFO.Instance;
   LFO_Syncs  : array (Tresses_Channels) of Boolean := (others => False);
   LFO_Values : array (Tresses_Channels) of Tresses.S16;

   type Voice_Parameters_Array is array (Tresses_Channels) of
     Voice_Parameters;

   In_Voice_Parameters : Voice_Parameters_Array :=
     (others => (Voice_Volume_CC => Param_Range'Last / 2,
                 Voice_Pan_CC    => Param_Range'Last / 2,
                 Voice_Param_4_CC => Param_Range'Last,
                 others          => 0));
   Out_Voice_Parameters : Voice_Parameters_Array := (others => (others => 0));

   Last_Key : array (MIDI.MIDI_Channel) of MIDI.MIDI_Key := (others => 0);

   FX_Send : array (MIDI.MIDI_Channel) of FX_Kind := (others => Bypass);

   Pan_For_Chan : array (MIDI.MIDI_Channel) of WNM_HAL.Audio_Pan :=
     (others => WNM_HAL.Init_Pan);

   Volume_For_Chan : array (MIDI.MIDI_Channel) of WNM_HAL.Audio_Volume :=
     (others => WNM_HAL.Init_Volume);

   Overall_Synth_Perf : WNM.Utils.Perf_Timer;
   Synth_Perf : array (Tresses_Channels) of WNM.Utils.Perf_Timer;

   G_CPU_Load : CPU_Load := 0.0 with Volatile, Atomic;
   G_Max_CPU_Load : CPU_Load := 0.0 with Volatile, Atomic;
   G_Count_Missed_Deadlines : HAL.UInt32 := 0 with Volatile, Atomic;

   -- Coproc Event Queue --
   package Coproc_Event_Queues
   is new WNM.Generic_Queue (Coproc.Message, "Synth coproc");
   Coproc_Event_Queue : Coproc_Event_Queues.Instance
     (WNM_Configuration.Coproc_Queue_Capacity);

   procedure Next_Points (Output : out WNM.Mixer.FX_Send_Buffers);

   function Vol_To_Param (V : MIDI.MIDI_Data)
                          return Tresses.Param_Range
     with Inline_Always;

   function To_Volume (V : Tresses.Param_Range)
                       return WNM_HAL.Audio_Volume
     with Inline_Always;

   function To_Pan (V : Tresses.Param_Range)
                    return WNM_HAL.Audio_Pan
     with Inline_Always;

   function To_Shape (V : MIDI.MIDI_Data)
                      return Tresses.LFO.Shape_Kind
     with Inline_Always;

   -----------
   -- Start --
   -----------

   procedure Start (This : in out WNM.Utils.Perf_Timer) is
   begin
      if WNM_Configuration.Individual_Synth_Perf_Enabled then
         WNM.Utils.Start (This);
      end if;
   end Start;

   ----------
   -- Stop --
   ----------

   procedure Stop (This : in out WNM.Utils.Perf_Timer) is
   begin
      if WNM_Configuration.Individual_Synth_Perf_Enabled then
         WNM.Utils.Stop (This);
      end if;
   end Stop;

   ------------------
   -- Vol_To_Param --
   ------------------

   function Vol_To_Param (V : MIDI.MIDI_Data)
                          return Tresses.Param_Range
   is
      V_Clamp : constant MIDI.MIDI_Data := MIDI.MIDI_Data'Min (V, 100);
      Ret : constant Tresses.Param_Range := Param_Range (V_Clamp) *
        (Param_Range'Last / Param_Range (100));
   begin
      return Ret;
   end Vol_To_Param;

   ---------------
   -- To_Volume --
   ---------------

   function To_Volume (V : Tresses.Param_Range)
                       return WNM_HAL.Audio_Volume
   is (WNM_HAL.Audio_Volume (V / 328));

   ------------
   -- To_Pan --
   ------------

   function To_Pan (V : Tresses.Param_Range)
                    return WNM_HAL.Audio_Pan
   is (WNM_HAL.Audio_Pan (V / 328));

   --------------
   -- To_Shape --
   --------------

   function To_Shape (V : MIDI.MIDI_Data)
                      return Tresses.LFO.Shape_Kind
   is (case V is
          when 0 => Tresses.LFO.Sine,
          when 1 => Tresses.LFO.Triangle,
          when 2 => Tresses.LFO.Ramp_Up,
          when 3 => Tresses.LFO.Ramp_Down,
          when 4 => Tresses.LFO.Exp_Up,
          when 5 => Tresses.LFO.Exp_Down,
          when others => Tresses.LFO.Random
      );

   -------------------
   -- Last_CPU_Load --
   -------------------

   function Last_CPU_Load return CPU_Load
   is (G_CPU_Load);

   ------------------
   -- Max_CPU_Load --
   ------------------

   function Max_CPU_Load return CPU_Load
   is (G_Max_CPU_Load);

   ----------------------
   -- Missed_Deadlines --
   ----------------------

   function Missed_Deadlines return HAL.UInt32
   is (G_Count_Missed_Deadlines);

   --------------------
   -- Synth_CPU_Load --
   --------------------

   function Synth_CPU_Load (Chan : MIDI.MIDI_Channel) return CPU_Load
   is (if WNM_Configuration.Individual_Synth_Perf_Enabled
         and then
          Chan in Synth_Perf'Range
       then WNM.Utils.Load (Synth_Perf (Chan))
       else 0.0);

   ------------------------
   -- Synth_CPU_Max_Load --
   ------------------------

   function Synth_CPU_Max_Load (Chan : MIDI.MIDI_Channel) return CPU_Load
   is (if WNM_Configuration.Individual_Synth_Perf_Enabled
         and then
          Chan in Synth_Perf'Range
       then WNM.Utils.Max_Load (Synth_Perf (Chan))
       else 0.0);

   --------------------------
   -- Synth_CPU_Load_Reset --
   --------------------------

   procedure Synth_CPU_Load_Reset (Chan : MIDI.MIDI_Channel) is
   begin
      if WNM_Configuration.Individual_Synth_Perf_Enabled
         and then
          Chan in Synth_Perf'Range
      then
         WNM.Utils.Reset (Synth_Perf (Chan));
      end if;
   end Synth_CPU_Load_Reset;

   ------------------------
   -- Clear_Max_CPU_Load --
   ------------------------

   procedure Clear_Max_CPU_Load is
   begin
      G_Max_CPU_Load := 0.0;
   end Clear_Max_CPU_Load;

   ----------------------------
   -- Clear_Missed_Deadlines --
   ----------------------------

   procedure Clear_Missed_Deadlines is
   begin
      G_Count_Missed_Deadlines := 0;
   end Clear_Missed_Deadlines;

   ----------------------
   -- Push_Copro_Event --
   ----------------------

   procedure Push_Copro_Event (Msg : WNM.Coproc.Message) is
   begin
      Coproc_Event_Queues.Push (Coproc_Event_Queue, Msg);
   end Push_Copro_Event;

   generic
      with procedure Process (Voice : in out Voice_Class);
   procedure With_Voice (Chan : Tresses_Channels);

   procedure With_Voice (Chan : Tresses_Channels) is
      S : constant Natural := Channel_Slot (Chan);
   begin
      if S = 0 then
         return;
      end if;
      case Kinds (Chan) is
         when Kick_Mode => Process (Slots (S).TK);
         when Snare_Mode => Process (Slots (S).TS);
         when Hihat_Mode => Process (Slots (S).HH);
         when Chord_Mode => Process (Slots (S).Chord);
         when Sample1_Mode | Sample2_Mode => Process (Slots (S).Sampler);
         when Bass_Mode | Lead_Mode => Process (Slots (S).Lead);
         when others => null;
      end case;
   end With_Voice;

   procedure Set_Engine (Chan : Tresses_Channels) is
      S : constant Natural := Channel_Slot (Chan);
      V : constant MIDI.MIDI_Data := Engines (Chan);
   begin
      if S = 0 then
         return;
      end if;
      case Kinds (Chan) is
         when Kick_Mode => Slots (S).TK.Set_Engine (Kick_Engines (V));
         when Snare_Mode => Slots (S).TS.Set_Engine (Snare_Engines (V));
         when Hihat_Mode => Slots (S).HH.Set_Engine (HH_Engines (V));
         when Bass_Mode | Lead_Mode => Slots (S).Lead.Set_Engine (Lead_Engines (V));
         when Chord_Mode =>
            Slots (S).Chord.Set_Engine (Chord_Engines (V));
            Slots (S).Chord.Init;
         when Sample1_Mode | Sample2_Mode =>
            Slots (S).Sampler.Set_Engine (Sampler_Engines (V));
         when others => null;
      end case;
   end Set_Engine;

   procedure Release_Channel (Chan : Tresses_Channels) is
      S : constant Natural := Channel_Slot (Chan);
   begin
      if S /= 0 then
         Owners (S) := -1;
         Free (Slots (S));
      end if;
      Channel_Slot (Chan) := 0;

      L_Peak (Chan) := 0;
      R_Peak (Chan) := 0;
   end Release_Channel;

   procedure Allocate_Voice (Chan : Tresses_Channels) is
      S : Voice_Slot := Voice_Slot'First;
   begin
      if Kinds (Chan) in MIDI_Mode | Reverb_Mode .. Bitcrush_Mode then
         return;
      end if;
      if Channel_Slot (Chan) = 0 then
         for I in Voice_Slot loop
            if Owners (I) = -1 then
               S := I;
               exit;
            elsif Ages (I) < Ages (S) then
               S := I;
            end if;
         end loop;
         if Owners (S) /= -1 then
            Release_Channel (Tresses_Channels (Owners (S)));
         end if;
         Owners (S) := Integer (Chan);
         Channel_Slot (Chan) := S;
         case Kinds (Chan) is
            when Kick_Mode => Slots (S) := new Slot_Rec'(B => null, Kind => Kick_Mode, TK => <>);
            when Snare_Mode => Slots (S) := new Slot_Rec'(B => null, Kind => Snare_Mode, TS => <>);
            when Hihat_Mode => Slots (S) := new Slot_Rec'(B => null, Kind => Hihat_Mode, HH => <>);
            when Chord_Mode => Slots (S) := new Slot_Rec'(B => null, Kind => Chord_Mode, Chord => <>);
            when Sample1_Mode | Sample2_Mode =>
               Slots (S) := new Slot_Rec'(B => null, Kind => Sample_Kind (Kinds (Chan)), Sampler => <>);
            when Bass_Mode | Lead_Mode =>
               Slots (S) := new Slot_Rec'(B => Macro_Buffers (S)'Access, Kind => Macro_Kind (Kinds (Chan)), Lead => <>);
               Slots (S).Lead.Set_User_Waveform (User_Waveform'Access);
            when others => null;
         end case;
         case Kinds (Chan) is
            when Kick_Mode =>
               Slots (S).TK.Init;
            when Snare_Mode =>
               Slots (S).TS.Init;
            when Hihat_Mode =>
               Slots (S).HH.Init;
            when Chord_Mode =>
               Slots (S).Chord.Init;
            when Sample1_Mode | Sample2_Mode =>
               Slots (S).Sampler.Init;
            when Bass_Mode | Lead_Mode =>
               Slots (S).Lead.Init;
            when others => null;
         end case;
         Set_Engine (Chan);
      else
         S := Channel_Slot (Chan);
      end if;
      for I in Voice_Slot loop
         if Ages (I) > Ages (S) then
            Ages (I) := Ages (I) - 1;
         end if;
      end loop;
      Ages (S) := Internal_Voice_Count;
   end Allocate_Voice;

   ---------------------------
   -- Process_Coproc_Events --
   ---------------------------

   procedure Process_Coproc_Events is
      use MIDI;
      use WNM.Coproc;

      Msg : WNM.Coproc.Message;
      Success : Boolean;
   begin
      loop
         Coproc_Event_Queues.Pop (Coproc_Event_Queue, Msg, Success);

         exit when not Success;

         case Msg.Kind is

            when WNM.Coproc.Buffer_Available =>

               Next_Points (WNM.Mixer.Mixer_Buffers (Msg.Buffer_Id));

               --  Send the buffers back to main CPU
               WNM.Coproc.Push_To_Main (Msg);

            when WNM.Coproc.Sample_Preview =>
               if Msg.MIDI_Evt.Kind = MIDI.Note_On then
                  Sample_Rec_Playback.Note_On (Msg.MIDI_Evt.Key);
               end if;

            when WNM.Coproc.MIDI_Event | WNM.Coproc.Voice_Config =>

               --  Ada.Text_IO.Put_Line ("Synth message is MIDI");
               --  Ada.Text_IO.Put_Line
               --    (Clock'Img & " - " &
               --     MIDI.Img (Msg.MIDI_Evt));

               if Msg.Kind = WNM.Coproc.Voice_Config
               then
                  declare
                     Chan : constant Tresses_Channels := Msg.MIDI_Evt.Chan;
                     Raw : constant MIDI.MIDI_Data := Msg.MIDI_Evt.Controller_Value;
                  begin
                     --  A full synchronization also terminates tails from the
                     --  previous project, even if its voice kind was the same.
                     Release_Channel (Chan);
                     if Raw <= Voice_Kind'Pos (Voice_Kind'Last) then
                        Kinds (Chan) := Voice_Kind'Val (Raw);
                     else
                        Kinds (Chan) := MIDI_Mode;
                     end if;
                  end;
               else
                  if Msg.MIDI_Evt.Kind = MIDI.Note_On then
                     Allocate_Voice (Msg.MIDI_Evt.Chan);
                  end if;
                  declare
                     Chan : constant Tresses_Channels := Msg.MIDI_Evt.Chan;
                     S : constant Natural := Channel_Slot (Chan);
                     procedure Process_Note (Voice : in out Voice_Class) is
                     begin
                        case Msg.MIDI_Evt.Kind is
                     when MIDI.Note_On =>

                        declare
                           Key : constant MIDI_Key := Msg.MIDI_Evt.Key;
                        begin
                           if Kinds (Chan) in Sample1_Mode | Sample2_Mode then
                              Slots (S).Sampler.Set_Sample
                                (Tresses.Param_MIDI (In_Voice_Parameters (Chan)(Voice_Param_1_CC)));
                              Slots (S).Sampler.Set_MIDI_Pitch (Key);
                           elsif Kinds (Chan) = Chord_Mode then
                              Slots (S).Chord.Key_On
                                (Key, Tresses.MIDI_Param (Msg.MIDI_Evt.Velocity));
                           else
                              Voice.Set_Pitch (Tresses.MIDI_Pitch
                                (Standard.MIDI.MIDI_UInt8 (Key)));
                           end if;

                           Voice.Note_On (Tresses.MIDI_Param
                                          (Msg.MIDI_Evt.Velocity));

                           Last_Key (Msg.MIDI_Evt.Chan) := Key;

                           if LFO_Syncs (Msg.MIDI_Evt.Chan) then
                              LFOs (Msg.MIDI_Evt.Chan).Sync;
                           end if;
                        end;

                     when MIDI.Note_Off =>

                        declare
                           Key : constant MIDI_Key := Msg.MIDI_Evt.Key;
                        begin
                           if Kinds (Chan) = Chord_Mode then
                              Slots (S).Chord.Key_Off (Msg.MIDI_Evt.Key);

                           elsif Last_Key (Msg.MIDI_Evt.Chan) = Key then
                              --  Only apply note_off if it matches the last
                              --  played key.
                              Voice.Note_Off;
                              Last_Key (Msg.MIDI_Evt.Chan) := 0;
                           end if;
                        end;

                           when others => null;
                        end case;
                     end Process_Note;
                     procedure Dispatch_Note is new With_Voice (Process_Note);
                  begin
                     case Msg.MIDI_Evt.Kind is
                        when MIDI.Note_On | MIDI.Note_Off => Dispatch_Note (Chan);
                     when MIDI.Continous_Controller =>
                        case Msg.MIDI_Evt.Controller is
                           when LFO_Compatible_CC =>

                              if Msg.MIDI_Evt.Controller in
                                Voice_Volume_CC | Voice_Pan_CC
                              then
                                 In_Voice_Parameters
                                   (Msg.MIDI_Evt.Chan)
                                   (Msg.MIDI_Evt.Controller)
                                   := Vol_To_Param
                                     (Msg.MIDI_Evt.Controller_Value);

                              else

                                 In_Voice_Parameters
                                   (Msg.MIDI_Evt.Chan)
                                   (Msg.MIDI_Evt.Controller)
                                   := Tresses.MIDI_Param
                                     (Msg.MIDI_Evt.Controller_Value);
                              end if;

                           when Voice_Engine_CC =>

                              Engines (Chan) := Msg.MIDI_Evt.Controller_Value;
                              Set_Engine (Chan);

                           when Voice_FX_CC =>
                              FX_Send (Msg.MIDI_Evt.Chan) :=
                                (case Msg.MIDI_Evt.Controller_Value is
                                    when FX_Select_Bypass     => Bypass,
                                    when FX_Select_Overdrive  => Overdrive,
                                    when FX_Select_Reverb     => Reverb,
                                    when FX_Select_Bitcrusher => Bitcrusher,
                                    when others => Bypass);

                           when Voice_LFO_Rate_CC =>
                              LFOs (Msg.MIDI_Evt.Chan).Set_Rate
                                (MIDI_Param (Msg.MIDI_Evt.Controller_Value),
                                 WNM_Configuration.Audio.Samples_Per_Buffer);

                           when Voice_LFO_Shape_CC =>
                              LFOs (Msg.MIDI_Evt.Chan).Set_Shape
                                (To_Shape (Msg.MIDI_Evt.Controller_Value));

                           when Voice_LFO_Amp_CC =>
                              LFOs (Msg.MIDI_Evt.Chan).Set_Amplitude
                                (MIDI_Param (Msg.MIDI_Evt.Controller_Value));

                           when Voice_LFO_Amp_Mode_CC =>
                              LFOs (Msg.MIDI_Evt.Chan).Set_Amp_Mode
                                (Tresses.LFO.Amplitude_Kind'Enum_Val
                                   (Msg.MIDI_Evt.Controller_Value));

                           when Voice_LFO_Target_CC =>
                              LFO_Targets (Msg.MIDI_Evt.Chan) :=
                                Msg.MIDI_Evt.Controller_Value;

                           when Voice_LFO_Loop_CC =>
                              LFOs (Msg.MIDI_Evt.Chan).Set_Loop_Mode
                                (if Msg.MIDI_Evt.Controller_Value /= 0
                                 then Tresses.LFO.Repeat
                                 else Tresses.LFO.One_Shot);

                           when Voice_LFO_Sync_CC =>
                              LFO_Syncs (Msg.MIDI_Evt.Chan) :=
                                Msg.MIDI_Evt.Controller_Value /= 0;

                           when others =>
                              null;
                        end case;
                        when others => null;
                     end case;
                  end;

               end if;


            when Synth_CPU_Crash =>
               raise Program_Error with "Synth exception requested";
         end case;
      end loop;
   end Process_Coproc_Events;

   -----------------------
   -- LFO_Current_Value --
   -----------------------

   function LFO_Current_Value (Chan : Tresses_Channels) return Tresses.S16 is
   begin
      return LFO_Values (Chan);
   end LFO_Current_Value;

   ---------------------------
   -- Param_Value_After_LFO --
   ---------------------------

   function Param_Value_After_LFO (Chan : Tresses_Channels)
                                   return Tresses.Param_Range
   is
      Target : constant MIDI.MIDI_Data := LFO_Targets (Chan);
   begin
      if Target in LFO_Compatible_CC then
         return Out_Voice_Parameters (Chan) (Target);
      else
         return 0;
      end if;
   end Param_Value_After_LFO;

   ----------------------------
   -- Param_Value_Before_LFO --
   ----------------------------

   function Param_Value_Before_LFO (Chan : Tresses_Channels)
                                    return Tresses.Param_Range
   is
      Target : constant MIDI.MIDI_Data := LFO_Targets (Chan);
   begin
      if Target in LFO_Compatible_CC then
         return In_Voice_Parameters (Chan) (Target);
      else
         return 0;
      end if;
   end  Param_Value_Before_LFO;

   -----------------
   -- Next_Points --
   -----------------

   procedure Next_Points (Output : out WNM.Mixer.FX_Send_Buffers)
   is
      Buffer, Aux_Buffer : WNM_HAL.Mono_Buffer;

      --------------
      -- Add_Clip --
      --------------

      function Add_Clip (A : Param_Range; B : S16) return Param_Range is
         Result : constant S32 := S32 (A) + S32 (B);
      begin
         if Result > S32 (Param_Range'Last) then
            return Param_Range'Last;
         elsif Result < S32 (Param_Range'First) then
            return Param_Range'First;
         else
            return Param_Range (Result);
         end if;
      end Add_Clip;

      ---------
      -- Mix --
      ---------

      procedure Mix (Chan : MIDI.MIDI_Channel) is
         FX : constant FX_Kind := FX_Send (Chan);
         Volume : constant Audio_Volume := Volume_For_Chan (Chan);
         Pan : constant Audio_Pan := Pan_For_Chan (Chan);

         L_Peak_Tmp, R_Peak_Tmp : S16;
      begin
         WNM_HAL.Mix (Output.L (FX), Output.R (FX),
                      Buffer, Volume, Pan, L_Peak_Tmp, R_Peak_Tmp);

         L_Peak (Chan) := L_Peak_Tmp;
         R_Peak (Chan) := R_Peak_Tmp;

         Utils.Peak_Decay (L_Peak_History (Chan));
         Utils.Peak_Decay (R_Peak_History (Chan));

         L_Peak_History (Chan) :=
           S16'Max (L_Peak_History (Chan), L_Peak (Chan));

         R_Peak_History (Chan) :=
           S16'Max (R_Peak_History (Chan), R_Peak (Chan));
      end Mix;
   begin
      Utils.Start (Overall_Synth_Perf);

      --  Take input params
      Out_Voice_Parameters := In_Voice_Parameters;

      --  Compute LFOs
      for Chan in LFOs'Range loop
         LFO_Values (Chan) := LFOs (Chan).Render;
      end loop;

      --  Apply LFOs
      for Chan in Tresses_Channels loop
         if LFO_Targets (Chan) in LFO_Compatible_CC then
            Out_Voice_Parameters (Chan)(LFO_Targets (Chan)) :=
              Add_Clip (Out_Voice_Parameters (Chan)(LFO_Targets (Chan)),
                        LFO_Values (Chan));
         end if;
      end loop;

      --  Set params
      for Chan in Tresses_Channels loop
         declare
            procedure Apply (Voice : in out Voice_Class) is
            begin
         Voice.Set_Param
           (1, Out_Voice_Parameters (Chan)(Voice_Param_1_CC));
         Voice.Set_Param
           (2, Out_Voice_Parameters (Chan)(Voice_Param_2_CC));
         Voice.Set_Param
           (3, Out_Voice_Parameters (Chan)(Voice_Param_3_CC));
         Voice.Set_Param
           (4, Out_Voice_Parameters (Chan)(Voice_Param_4_CC));
            end Apply;
            procedure Dispatch is new With_Voice (Apply);
         begin
            Dispatch (Chan);
            if Channel_Slot (Chan) /= 0 and then
              Kinds (Chan) in Sample1_Mode | Sample2_Mode
            then
               Slots (Channel_Slot (Chan)).Sampler.Set_Sample
                 (Tresses.Param_MIDI (Out_Voice_Parameters (Chan)(Voice_Param_1_CC)));
            end if;
         end;

         Pan_For_Chan (Chan) := To_Pan
           (Out_Voice_Parameters (Chan)(Voice_Pan_CC));

         Volume_For_Chan (Chan) := To_Volume
            (Out_Voice_Parameters (Chan)(Voice_Volume_CC));
      end loop;

      Output.Parameters := (others => (others => Tresses.MIDI_Param (63)));
      Output.Parameters (Overdrive)(1) := Tresses.MIDI_Param (127);
      --  FX remain global buses. If several tracks automate the same bus,
      --  the highest-numbered configured track supplies its parameters.
      for Chan in Tresses_Channels loop
         case Kinds (Chan) is
            when Reverb_Mode => Output.Parameters (Reverb) := Out_Voice_Parameters (Chan);
            when Drive_Mode => Output.Parameters (Overdrive) := Out_Voice_Parameters (Chan);
            when Bitcrush_Mode => Output.Parameters (Bitcrusher) := Out_Voice_Parameters (Chan);
            when others => null;
         end case;
      end loop;

      if WNM.Mixer.Get_Sample_Rec_Mode in WNM.Mixer.Play then
         --  We are in sample record playback mode, the synth CPU is now in
         --  charge of playing the recorded sample.

         Sample_Rec_Playback.Render (Output.R (Bypass));
         Output.L (Bypass) := Output.R (Bypass);

      elsif WNM.Mixer.Get_Sample_Rec_Mode in WNM.Mixer.Saving then
         --  Do nothing...
         null;
      else

         --  Regular synthesis of all channels

         for Chan in Tresses_Channels loop
            if Channel_Slot (Chan) /= 0 then
               declare
                  S : constant Voice_Slot := Channel_Slot (Chan);
               begin
                  Start (Synth_Perf (Chan));
                  case Kinds (Chan) is
                     when Kick_Mode => Slots (S).TK.Render (Buffer);
                     when Snare_Mode => Slots (S).TS.Render (Buffer);
                     when Hihat_Mode => Slots (S).HH.Render (Buffer);
                     when Bass_Mode | Lead_Mode => Slots (S).Lead.Render (Buffer, Aux_Buffer);
                     when Chord_Mode => Slots (S).Chord.Render (Buffer);
                     when Sample1_Mode | Sample2_Mode => Slots (S).Sampler.Render (Buffer);
                     when others => Buffer := (others => 0);
                  end case;
                  Mix (Chan);
                  Stop (Synth_Perf (Chan));
               end;
            end if;
         end loop;
      end if;

      Utils.Stop (Overall_Synth_Perf);

      G_CPU_Load := Utils.Load (Overall_Synth_Perf);

      if G_CPU_Load > 100.0 then
         G_Count_Missed_Deadlines := G_Count_Missed_Deadlines + 1;
      end if;

      if G_CPU_Load > G_Max_CPU_Load then
         G_Max_CPU_Load := G_CPU_Load;
      end if;

   end Next_Points;

   ----------------------
   -- Lead_Engine_Last --
   ----------------------

   function Lead_Engine_Last return MIDI.MIDI_Data
   is (Lead_Engine_Range'Last);

   ---------------------
   -- Lead_Engine_Img --
   ---------------------

   function Lead_Engine_Img (Engine : MIDI.MIDI_Data) return String
   is (Tresses.Img (Lead_Engines (Engine)));

   ----------------------
   -- Lead_Param_Label --
   ----------------------

   function Lead_Param_Label (Engine : MIDI.MIDI_Data;
                              Id : Tresses.Param_Id)
                              return String
   is
      E : constant Tresses.Engines := Lead_Engines (Engine);
   begin
      return Tresses.Macro.Param_Label (E, Id);
   end Lead_Param_Label;

   ----------------------------
   -- Lead_Param_Short_Label --
   ----------------------------

   function Lead_Param_Short_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id)
                                    return Tresses.Short_Label
   is
      E : constant Tresses.Engines := Lead_Engines (Engine);
   begin
      return Tresses.Macro.Param_Short_Label (E, Id);
   end Lead_Param_Short_Label;

   ----------------------
   -- Kick_Engine_Last --
   ----------------------

   function Kick_Engine_Last return MIDI.MIDI_Data
   is (Kick_Engine_Range'Last);

   ---------------------
   -- Kick_Engine_Img --
   ---------------------

   function Kick_Engine_Img (Engine : MIDI.MIDI_Data) return String
   is (WNM.Voices.Kick_Voice.Img (Kick_Engines (Engine)));

   ----------------------
   -- Kick_Param_Label --
   ----------------------

   function Kick_Param_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id) return String
   is
      V : WNM.Voices.Kick_Voice.Instance;
   begin
      V.Set_Engine (Kick_Engines (Engine));
      return V.Param_Label (Id);
   end Kick_Param_Label;

   ----------------------------
   -- Kick_Param_Short_Label --
   ----------------------------

   function Kick_Param_Short_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id)
                                    return Tresses.Short_Label
   is
      V : WNM.Voices.Kick_Voice.Instance;
   begin
      V.Set_Engine (Kick_Engines (Engine));
      return V.Param_Short_Label (Id);
   end Kick_Param_Short_Label;

   -----------------------
   -- Snare_Engine_Last --
   -----------------------

   function Snare_Engine_Last return MIDI.MIDI_Data
   is (Snare_Engine_Range'Last);

   ----------------------
   -- Snare_Engine_Img --
   ----------------------

   function Snare_Engine_Img (Engine : MIDI.MIDI_Data) return String
   is (WNM.Voices.Snare_Voice.Img (Snare_Engines (Engine)));

   -----------------------
   -- Snare_Param_Label --
   -----------------------

   function Snare_Param_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id) return String
   is
      V : WNM.Voices.Snare_Voice.Instance;
   begin
      V.Set_Engine (Snare_Engines (Engine));
      return V.Param_Label (Id);
   end Snare_Param_Label;

   -----------------------------
   -- Snare_Param_Short_Label --
   -----------------------------

   function Snare_Param_Short_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id)
                                    return Tresses.Short_Label
   is
      V : WNM.Voices.Snare_Voice.Instance;
   begin
      V.Set_Engine (Snare_Engines (Engine));
      return V.Param_Short_Label (Id);
   end Snare_Param_Short_Label;

   -----------------------
   -- Hihat_Engine_Last --
   -----------------------

   function Hihat_Engine_Last return MIDI.MIDI_Data
   is (HH_Engine_Range'Last);

   ----------------------
   -- Hihat_Engine_Img --
   ----------------------

   function Hihat_Engine_Img (Engine : MIDI.MIDI_Data) return String
   is (WNM.Voices.Hihat_Voice.Img (HH_Engines (Engine)));

   ------------------------
   -- Cymbal_Param_Label --
   ------------------------

   function Hihat_Param_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id) return String
   is
      V : WNM.Voices.Hihat_Voice.Instance;
   begin
      V.Set_Engine (HH_Engines (Engine));
      return V.Param_Label (Id);
   end Hihat_Param_Label;

   ------------------------------
   -- Cymbal_Param_Short_Label --
   ------------------------------

   function Hihat_Param_Short_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id)
                                      return Tresses.Short_Label
   is
      V : WNM.Voices.Hihat_Voice.Instance;
   begin
      V.Set_Engine (HH_Engines (Engine));
      return V.Param_Short_Label (Id);
   end Hihat_Param_Short_Label;

   -------------------------
   -- Sampler_Engine_Last --
   -------------------------

   function Sampler_Engine_Last return MIDI.MIDI_Data
   is (Sampler_Engine_Range'Last);

   ------------------------
   -- Sampler_Engine_Img --
   ------------------------

   function Sampler_Engine_Img (Engine : MIDI.MIDI_Data) return String
   is (Voices.Sampler_Voice.Img (Sampler_Engines (Engine)));

   -------------------------
   -- Sampler_Param_Label --
   -------------------------

   function Sampler_Param_Label (Engine : MIDI.MIDI_Data;
                                 Id   : Tresses.Param_Id)
                                 return String
   is
      V : WNM.Voices.Sampler_Voice.Instance;
   begin
      V.Set_Engine (Sampler_Engines (Engine));
      return V.Param_Label (Id);
   end Sampler_Param_Label;

   -------------------------------
   -- Sampler_Param_Short_Label --
   -------------------------------

   function Sampler_Param_Short_Label (Engine : MIDI.MIDI_Data;
                                       Id   : Tresses.Param_Id)
                                       return Tresses.Short_Label
   is
      V : WNM.Voices.Sampler_Voice.Instance;
   begin
      V.Set_Engine (Sampler_Engines (Engine));
      return V.Param_Short_Label (Id);
   end Sampler_Param_Short_Label;

   ------------------------
   -- Reverb_Param_Label --
   ------------------------

   function Reverb_Param_Label (Id : Tresses.Param_Id)
                                 return String
   is (Mixer.FX_Reverb.Param_Label (Id));

   ------------------------------
   -- Reverb_Param_Short_Label --
   ------------------------------

   function Reverb_Param_Short_Label (Id : Tresses.Param_Id)
                                       return Tresses.Short_Label
   is (Mixer.FX_Reverb.Param_Short_Label (Id));

   -----------------------
   -- Drive_Param_Label --
   -----------------------

   function Drive_Param_Label (Id : Tresses.Param_Id)
                               return String
   is (Mixer.FX_Drive.Param_Label (Id));

   -----------------------------
   -- Drive_Param_Short_Label --
   -----------------------------

   function Drive_Param_Short_Label (Id : Tresses.Param_Id)
                                     return Tresses.Short_Label
   is (Mixer.FX_Drive.Param_Short_Label (Id));

   --------------------------
   -- Bitcrush_Param_Label --
   --------------------------

   function Bitcrush_Param_Label (Id : Tresses.Param_Id)
                               return String
   is (Mixer.FX_Bitcrush.Param_Label (Id));

   --------------------------------
   -- Bitcrush_Param_Short_Label --
   --------------------------------

   function Bitcrush_Param_Short_Label (Id : Tresses.Param_Id)
                                        return Tresses.Short_Label
   is (Mixer.FX_Bitcrush.Param_Short_Label (Id));

   -----------------------
   -- Chord_Engine_Last --
   -----------------------

   function Chord_Engine_Last return MIDI.MIDI_Data
   is (Chord_Engine_Range'Last);

   ----------------------
   -- Chord_Engine_Img --
   ----------------------

   function Chord_Engine_Img (Engine : MIDI.MIDI_Data) return String
   is (Voices.Chord_Voice.Img (Chord_Engines (Engine)));

   -----------------------
   -- Chord_Param_Label --
   -----------------------

   function Chord_Param_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id)
                               return String
   is
      V : WNM.Voices.Chord_Voice.Instance;
   begin
      V.Set_Engine (Chord_Engines (Engine));
      return V.Param_Label (Id);
   end Chord_Param_Label;

   -----------------------------
   -- Chord_Param_Short_Label --
   -----------------------------

   function Chord_Param_Short_Label (Engine : MIDI.MIDI_Data;
                                    Id : Tresses.Param_Id)
                                     return Tresses.Short_Label
   is
      V : WNM.Voices.Chord_Voice.Instance;
   begin
      V.Set_Engine (Chord_Engines (Engine));
      return V.Param_Short_Label (Id);
   end Chord_Param_Short_Label;

begin
   for S in Voice_Slot loop
      Ages (S) := S;
   end loop;
end WNM.Synth;
