; 
; Copyright 2011-2013 Jeff Bush
; 
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
; 
;     http://www.apache.org/licenses/LICENSE-2.0
; 
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.
; 

				FRAME_BUFFER_ADDRESS = 0x10000000

				.regalias tmp s0
				.regalias ptr s1
				.regalias ycoord s2
				.regalias mask s3
				.regalias max_iterations s4
				.regalias four f5
				.regalias cmpresult s6
				.regalias xstep f7
				.regalias ystep f8
				.regalias xleft f9
				.regalias ytop f10
				
				.regalias xcoord v0
				.regalias x vf1
				.regalias y vf2
				.regalias xx vf3
				.regalias yy vf4
				.regalias tmp0 vf5
				.regalias x0 vf6
				.regalias y0 vf7
				.regalias iteration v8

_start:			tmp = 15
				cr30 = tmp				; start all strands

				; Load some constants
				four = 4.0
				xleft = -2.0
				xstep = 0.00390625		; 2.5 / 640
				ytop = -1.0
				ystep = 0.004166666		; 2.0 / 480
				max_iterations = 255

new_frame:		tmp = cr0				; get my strand id
				tmp = tmp << 4			; Multiply by 16 pixels
				xcoord = mem_l[initial_xcoords]
				xcoord = xcoord + tmp	; Add strand offset
				ycoord = 0

				ptr = FRAME_BUFFER_ADDRESS
				tmp = cr0			; get my strand id
				tmp = tmp << 6		; Multiply by 64 bytes
				ptr = ptr + tmp		; Offset pointer to interleave

				; Set up to compute pixel values
fill_loop:		v1 = 0	; x 
				v2 = 0	; y		
				iteration = 0

				; Convert coordinate space				
				x0 = itof(xcoord)
				x0 = x0 * xstep
				x0 = x0 + xleft
				y0 = itof(ycoord)
				y0 = y0 * ystep
				y0 = y0 + ytop
				
				; Determine if pixels are part of the set (16 pixels at a time)
escape_loop:	xx = x * x
				yy = y * y
				tmp0 = xx + yy
				mask = tmp0 < four
				cmpresult = iteration < max_iterations
				mask = mask & cmpresult		; while (x**2 + y**2 < 4 && iteration < max_iteration)
				if !mask goto write_pixels
				
				; y = 2 * x * y + y0
				y = x * y			
				y = y + y			; times two
				y = y + y0
				
				; x = x**2 - y**2 + x0
				x = xx - yy
				x = x + x0
				iteration{mask} = iteration + 1
				goto escape_loop

				; Write out pixels
write_pixels:	mask = iteration == max_iterations	; Determine which pixels are in the set and save it

				; Scale up colors for more constrast
				iteration = iteration << 2
				iteration = iteration + 40
				cmpresult = iteration > 255

				; Clamp values that have overflowed
				tmp = 255
				iteration{cmpresult} = tmp

				iteration{mask} = 0				; Color pixels in the set black
				mem_l[ptr] = iteration
				dflush(ptr)
				
				; Increment horizontally. Strands are interleaved,
				; each one does 16 pixels, then skips forward 64.
				ptr = ptr + 256
				xcoord = xcoord + 64

				tmp = getlane(xcoord, 0)
				tmp = tmp < 640
				if tmp goto fill_loop

				; Past end of line.  Wrap around to the next line.
				xcoord = xcoord - 640 
				ycoord = ycoord + 1
				tmp = ycoord == 480
				if !tmp goto fill_loop

done:			goto done

				.align 64
initial_xcoords: .word 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

