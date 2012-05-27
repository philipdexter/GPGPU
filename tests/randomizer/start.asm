_start		s2 = 0xf
			cr30 = s2		; Enable all strands
			s2 = cr0		; Get strand ID
			
			; set up address of private memory region (s0 is public and is left set to 0)
			s1 = s2 + 1	
			s1 = s1 << 17	; Multiply by 128k, so each strand starts on a new page
			v1 = s1			; set v1 as the same for now

			; Compute branch address			
			s2 = s2 << 8	; Multiply by 256 bytes (64 instructions)
			pc = pc + s2	; jump to start address for this strand
			
			