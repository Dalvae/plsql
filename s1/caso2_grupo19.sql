-- caso 2: postergacion de cuotas
-- grupo 19 - PRY2206

-- parametros de entrada
VARIABLE b_nro_cliente NUMBER;
VARIABLE b_nro_solicitud NUMBER;
VARIABLE b_cuotas_postergar NUMBER;

-- cambiar estos valores para cada cliente
BEGIN
    :b_nro_cliente      := 67;    -- karen pradenas
    :b_nro_solicitud    := 3004;  -- credito automotriz
    :b_cuotas_postergar := 1;
END;
/

DECLARE
    -- datos del credito
    v_nombre_credito    VARCHAR2(50);
    v_ultima_cuota_nro  NUMBER(3);
    v_ultima_cuota_fecha DATE;
    v_ultima_cuota_valor NUMBER(12);
    
    -- para verificar condonacion
    v_creditos_anio_ant NUMBER(3);
    v_anio_anterior     NUMBER(4);
    
    v_tasa_interes      NUMBER(5,4);
    v_nueva_cuota_nro   NUMBER(3);
    v_nueva_cuota_fecha DATE;
    v_nueva_cuota_valor NUMBER(12);

BEGIN
    v_anio_anterior := EXTRACT(YEAR FROM SYSDATE) - 1;

    -- traemos datos del credito y la ultima cuota
    SELECT cr.nombre_credito,
           MAX(ccc.nro_cuota),
           MAX(ccc.fecha_venc_cuota),
           MAX(ccc.valor_cuota)
      INTO v_nombre_credito,
           v_ultima_cuota_nro,
           v_ultima_cuota_fecha,
           v_ultima_cuota_valor
      FROM CREDITO_CLIENTE cc
      JOIN CREDITO cr ON cc.cod_credito = cr.cod_credito
      JOIN CUOTA_CREDITO_CLIENTE ccc ON cc.nro_solic_credito = ccc.nro_solic_credito
     WHERE cc.nro_solic_credito = :b_nro_solicitud
       AND cc.nro_cliente = :b_nro_cliente
     GROUP BY cr.nombre_credito;

    DBMS_OUTPUT.PUT_LINE('Credito: ' || v_nombre_credito);
    DBMS_OUTPUT.PUT_LINE('Ultima cuota: ' || v_ultima_cuota_nro);

    -- contamos creditos del año anterior para ver si aplica condonacion
    SELECT COUNT(*)
      INTO v_creditos_anio_ant
      FROM CREDITO_CLIENTE
     WHERE nro_cliente = :b_nro_cliente
       AND EXTRACT(YEAR FROM fecha_otorga_cred) = v_anio_anterior;

    -- si tiene mas de 1 credito, condonamos la ultima cuota
    IF v_creditos_anio_ant > 1 THEN
        UPDATE CUOTA_CREDITO_CLIENTE
           SET fecha_pago_cuota = fecha_venc_cuota,
               monto_pagado = valor_cuota,
               saldo_por_pagar = 0
         WHERE nro_solic_credito = :b_nro_solicitud
           AND nro_cuota = v_ultima_cuota_nro;

        DBMS_OUTPUT.PUT_LINE('Condonacion aplicada en cuota ' || v_ultima_cuota_nro);
    END IF;

    v_tasa_interes := 0;
    
    IF UPPER(v_nombre_credito) LIKE '%HIPOTECARIO%' THEN
        -- hipotecario: 1 cuota sin interes, 2 cuotas 0.5%
        IF :b_cuotas_postergar = 1 THEN
            v_tasa_interes := 0;
        ELSIF :b_cuotas_postergar = 2 THEN
            v_tasa_interes := 0.005;
        END IF;
        
    ELSIF UPPER(v_nombre_credito) LIKE '%CONSUMO%' THEN
        v_tasa_interes := 0.01;  -- 1%
        
    ELSIF UPPER(v_nombre_credito) LIKE '%AUTOMOTRIZ%' THEN
        v_tasa_interes := 0.02;  -- 2%
    END IF;

    DBMS_OUTPUT.PUT_LINE('Tasa: ' || (v_tasa_interes * 100) || '%');

    -- creamos las nuevas cuotas con un for
    FOR i IN 1 .. :b_cuotas_postergar LOOP
        
        v_nueva_cuota_nro := v_ultima_cuota_nro + i;
        v_nueva_cuota_fecha := ADD_MONTHS(v_ultima_cuota_fecha, i);
        v_nueva_cuota_valor := ROUND(v_ultima_cuota_valor * (1 + v_tasa_interes), 0);

        -- insertamos la nueva cuota (los campos de pago quedan null)
        INSERT INTO CUOTA_CREDITO_CLIENTE (
            nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota,
            fecha_pago_cuota, monto_pagado, saldo_por_pagar, cod_forma_pago
        ) VALUES (
            :b_nro_solicitud, v_nueva_cuota_nro, v_nueva_cuota_fecha, v_nueva_cuota_valor,
            NULL, NULL, NULL, NULL
        );

        DBMS_OUTPUT.PUT_LINE('Nueva cuota ' || v_nueva_cuota_nro || ' - $' || v_nueva_cuota_valor);
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Proceso terminado ok');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('error: no se encontro el credito');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('error: ' || SQLERRM);
        ROLLBACK;
END;
/
