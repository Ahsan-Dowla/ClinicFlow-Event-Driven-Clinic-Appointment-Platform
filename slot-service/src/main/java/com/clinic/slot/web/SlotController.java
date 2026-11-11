package com.clinic.slot.web;

import com.clinic.slot.service.SlotService;
import com.clinic.slot.slot.SlotResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SlotController {
    private final SlotService slotService;

    public SlotController(SlotService slotService) {
        this.slotService = slotService;
    }

    @GetMapping("/slots/{id}")
    public SlotResponse getSlot(@PathVariable("id") Long id) {
        return slotService.getSlot(id);
    }
}
