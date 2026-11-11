package com.clinic.appointment.slot;

import com.clinic.appointment.web.ApiException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Component
public class SlotClient {
    private final RestClient restClient;

    public SlotClient(RestClient slotServiceRestClient) {
        this.restClient = slotServiceRestClient;
    }

    public SlotDetails getSlot(Long id, String authorization) {
        try {
            return restClient.get().uri("/slots/{id}", id)
                    .header(HttpHeaders.AUTHORIZATION, authorization)
                    .retrieve().body(SlotDetails.class);
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) {
                throw new ApiException(HttpStatus.NOT_FOUND, "Slot not found");
            }
            throw new ApiException(HttpStatus.BAD_GATEWAY, "Slot service rejected the slot lookup");
        } catch (ResourceAccessException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "Slot service is unavailable");
        }
    }

    public DoctorDetails getDoctor(Long id, String authorization) {
        try {
            return restClient.get().uri("/doctors/{id}", id)
                    .header(HttpHeaders.AUTHORIZATION, authorization)
                    .retrieve().body(DoctorDetails.class);
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) {
                throw new ApiException(HttpStatus.NOT_FOUND, "Doctor not found");
            }
            throw new ApiException(HttpStatus.BAD_GATEWAY, "Slot service rejected the doctor lookup");
        } catch (ResourceAccessException exception) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "Slot service is unavailable");
        }
    }
}
