-- REHEARSAL ONLY. Requires 202610300002 in a TEST copy, not the live project.
-- The final ROLLBACK preserves both legacy and relational destinations.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
lock table public.catalog_core, public.shared_recipes in share mode;
-- Private staging objects belong to this transaction and disappear on ROLLBACK.
create schema cocinapp_rehearsal;
revoke all on schema cocinapp_rehearsal from public, anon, authenticated;
create function cocinapp_rehearsal.norm(t text) returns text language sql immutable
as $$ select lower(translate(regexp_replace(trim(t), '\s+', ' ', 'g'), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')) $$;
create function cocinapp_rehearsal.key_id(kind text, old_id text) returns uuid language sql immutable
as $$ select md5('cocinapp-v1|' || kind || '|' || old_id)::uuid $$;
do $$ begin
  if exists(select 1 from public.categories) or exists(select 1 from public.units)
    or exists(select 1 from public.ingredients) or exists(select 1 from public.recipes)
    or exists(select 1 from public.dietary_tags) then
    raise exception 'El ensayo requiere destinos relacionales vacíos. No sobrescribe datos nuevos.';
  end if;
  if (select count(*) from public.catalog_core where catalog_key='main') <> 1
    or (select count(*) from public.shared_recipes where catalog_key='main') <> 1 then
    raise exception 'Faltan los catálogos fuente main.';
  end if;
end $$;
create table cocinapp_rehearsal.src_core as select payload from public.catalog_core where catalog_key='main';
create table cocinapp_rehearsal.src_recipes(legacy_id text primary key, body jsonb not null, origin text not null);
insert into cocinapp_rehearsal.src_recipes select x->>'id', x, 'seed'
from jsonb_array_elements($seed$[{"id": "quinoa-bowl", "name": "Bowl de quinoa y verduras", "description": "Verduras asadas, quinoa y aderezo de limón.", "category": "Almuerzo", "minutes": 30, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Quinoa", "quantity": 150, "unit": "g"}, {"name": "Tomates cherry", "quantity": 150, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}, {"name": "Limón", "quantity": 1, "unit": "u"}], "steps": ["Cociná la quinoa según el envase.", "Cortá los tomates y mezclalos con aceite de oliva.", "Serví la quinoa con las verduras y terminá con limón."], "stepMeta": [{"durationMinutes": 15, "stepIngredients": [{"name": "Quinoa", "quantity": 150, "unit": "g"}], "utensils": ["Colador fino", "Olla con tapa"], "temperature": "Hervor suave", "tip": "Enjuagá la quinoa antes de cocinarla para quitarle el sabor amargo.", "warning": "Usá el colador fino para no perder los granos."}, {"durationMinutes": 5, "stepIngredients": [{"name": "Tomates cherry", "quantity": 150, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}], "utensils": ["Tabla", "Cuchillo", "Bol"], "tip": "Cortá los tomates justo antes de servir para conservar su textura."}, {"durationMinutes": 2, "stepIngredients": [{"name": "Limón", "quantity": 1, "unit": "u"}], "utensils": ["Fuente para servir"], "specialInstructions": "Probá y ajustá el limón justo antes de llevar el plato a la mesa."}], "symbol": "🥗", "color": "green", "featured": true, "dietaryTags": ["Sin TACC", "Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/quinoa-bowl.webp", "imageAlt": "Bowl de quinoa con tomates cherry y verduras asadas servido en cerámica clara"}, {"id": "pumpkin-pasta", "name": "Pasta cremosa de calabaza", "description": "Una salsa suave con salvia y queso rallado.", "category": "Cena", "minutes": 25, "portions": 3, "difficulty": "Intermedia", "ingredients": [{"name": "Pasta", "quantity": 300, "unit": "g"}, {"name": "Calabaza", "quantity": 400, "unit": "g"}, {"name": "Queso rallado", "quantity": 60, "unit": "g"}], "steps": ["Cociná la pasta y reservá un poco del agua.", "Cociná la calabaza hasta que esté tierna y procesala.", "Mezclá la salsa con la pasta y terminá con queso rallado."], "stepMeta": [{"minutes": 10, "tip": "Reservá una taza del agua de cocción para ajustar la textura de la salsa."}, {"minutes": 12, "tip": "Procesá la calabaza caliente con cuidado y agregá líquido de a poco."}], "symbol": "🍝", "color": "gold", "featured": true, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/pumpkin-pasta.webp", "imageAlt": "Pasta cremosa de calabaza con queso rallado y hojas de salvia"}, {"id": "chickpea-salad", "name": "Ensalada tibia de garbanzos", "description": "Garbanzos crocantes, hojas frescas y yogur.", "category": "Almuerzo", "minutes": 20, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Garbanzos", "quantity": 250, "unit": "g"}, {"name": "Hojas verdes", "quantity": 100, "unit": "g"}, {"name": "Yogur", "quantity": 100, "unit": "g"}], "steps": ["Salteá los garbanzos hasta que estén dorados.", "Lavá y escurrí las hojas verdes.", "Serví todo con yogur."], "stepMeta": [{"minutes": 8, "tip": "Secá los garbanzos antes de saltearlos para que doren mejor."}], "symbol": "🥙", "color": "pink", "dietaryTags": ["Sin TACC", "Vegetariana", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/chickpea-salad.webp", "imageAlt": "Ensalada tibia de garbanzos dorados con hojas verdes y yogur"}, {"id": "chicken-rice", "name": "Pollo con arroz integral", "description": "Pollo dorado con arroz y tomates cherry frescos.", "category": "Cena", "minutes": 35, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Pechuga de pollo", "quantity": 300, "unit": "g"}, {"name": "Arroz integral", "quantity": 160, "unit": "g"}, {"name": "Tomates cherry", "quantity": 120, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 20, "unit": "ml"}], "steps": ["Cociná el arroz integral según las indicaciones del envase.", "Cortá el pollo y doralo en una sartén con el aceite de oliva.", "Serví el pollo sobre el arroz y agregá los tomates cortados."], "stepMeta": [{"durationMinutes": 25, "stepIngredients": [{"name": "Arroz integral", "quantity": 160, "unit": "g"}], "utensils": ["Olla con tapa"], "temperature": "Hervor suave", "tip": "Dejá reposar el arroz tapado durante 5 minutos al apagar el fuego."}, {"durationMinutes": 10, "stepIngredients": [{"name": "Pechuga de pollo", "quantity": 300, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 20, "unit": "ml"}], "utensils": ["Tabla para carnes", "Cuchillo", "Sartén"], "temperature": "Fuego medio-alto", "warning": "Lavá manos y utensilios después de manipular pollo crudo."}, {"durationMinutes": 4, "stepIngredients": [{"name": "Tomates cherry", "quantity": 120, "unit": "g"}], "utensils": ["Tabla", "Cuchillo"], "tip": "Agregá los tomates al final para conservar su frescura."}], "symbol": "🍗", "color": "blue", "dietaryTags": ["Sin TACC", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/chicken-rice.webp", "imageAlt": "Pollo dorado con arroz integral y tomates cherry servido en un plato"}, {"id": "yogurt-fruit", "name": "Yogur con banana y avena", "description": "Un desayuno rápido con fruta y avena.", "category": "Desayuno", "minutes": 8, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Yogur", "quantity": 180, "unit": "g"}, {"name": "Banana", "quantity": 1, "unit": "u"}, {"name": "Avena", "quantity": 40, "unit": "g"}], "steps": ["Serví el yogur en un bol.", "Cortá la banana y agregala con la avena."], "stepMeta": [{"tip": "Agregá la avena justo antes de comer para mantener su textura."}], "symbol": "🥣", "color": "pink", "calories": 310, "featured": true, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/yogurt-fruit.webp", "imageAlt": "Bol de yogur con rodajas de banana y avena"}, {"id": "apple-toast", "name": "Tostadas con manzana", "description": "Merienda simple con fruta y queso untable.", "category": "Merienda", "minutes": 10, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Manzana", "quantity": 1, "unit": "u"}, {"name": "Queso untable", "quantity": 40, "unit": "g"}], "steps": ["Tostá el pan integral.", "Untá el queso y sumá la manzana en láminas."], "symbol": "🍎", "color": "gold", "calories": 285, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/apple-toast.webp", "imageAlt": "Tostadas integrales con queso untable y láminas de manzana"}, {"id": "vegetable-omelette", "name": "Omelette de verduras", "description": "Huevos, espinaca y tomates en una cena simple y completa.", "category": "Cena", "minutes": 15, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Huevos", "quantity": 2, "unit": "u"}, {"name": "Espinaca", "quantity": 80, "unit": "g"}, {"name": "Tomates cherry", "quantity": 80, "unit": "g"}], "steps": ["Batí los huevos.", "Salteá la espinaca y los tomates.", "Agregá los huevos y cociná de ambos lados."], "symbol": "🍳", "color": "gold", "calories": 340, "dietaryTags": ["Sin TACC", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/vegetable-omelette.webp", "imageAlt": "Omelette de espinaca y tomates cherry servido en un plato claro"}, {"id": "lentil-stew", "name": "Guiso rápido de lentejas", "description": "Lentejas, tomate y verduras en un plato cálido de todos los días.", "category": "Cena", "minutes": 40, "portions": 4, "difficulty": "Intermedia", "ingredients": [{"name": "Lentejas", "quantity": 400, "unit": "g"}, {"name": "Tomate", "quantity": 2, "unit": "u"}, {"name": "Zanahoria", "quantity": 2, "unit": "u"}], "steps": ["Cortá las verduras.", "Cocinalas con el tomate.", "Sumá las lentejas y cociná hasta integrar."], "symbol": "🍲", "color": "pink", "dietaryTags": ["Sin TACC", "Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/lentil-stew.webp", "imageAlt": "Guiso de lentejas con tomate y zanahoria servido en un cuenco"}, {"id": "avocado-toast", "name": "Tostadas con palta y huevo", "description": "Un desayuno cremoso, fresco y listo en pocos minutos.", "category": "Desayuno", "minutes": 12, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Palta", "quantity": 1, "unit": "u"}, {"name": "Huevos", "quantity": 1, "unit": "u"}], "steps": ["Tostá el pan.", "Pisá la palta y condimentá.", "Cociná el huevo y servilo sobre las tostadas."], "symbol": "🥑", "color": "green", "calories": 390, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/avocado-toast.webp", "imageAlt": "Tostadas integrales con palta y huevo cocido"}, {"id": "banana-pancakes", "name": "Panqueques de banana y avena", "description": "Panqueques suaves sin harina, ideales para empezar el día.", "category": "Desayuno", "minutes": 18, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Banana", "quantity": 2, "unit": "u"}, {"name": "Avena", "quantity": 100, "unit": "g"}, {"name": "Huevos", "quantity": 2, "unit": "u"}], "steps": ["Procesá la banana, la avena y los huevos.", "Volcá porciones en una sartén caliente.", "Doralos de ambos lados y serví."], "symbol": "🥞", "color": "blue", "calories": 360, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/banana-pancakes.webp", "imageAlt": "Panqueques de banana y avena apilados en un plato"}, {"id": "scrambled-eggs-toast", "name": "Huevos revueltos con tostadas", "description": "Desayuno tibio y rápido con huevos cremosos.", "category": "Desayuno", "minutes": 12, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Huevos", "quantity": 2, "unit": "u"}, {"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Leche", "quantity": 30, "unit": "ml"}], "steps": ["Batí los huevos con la leche.", "Cocinalos a fuego bajo revolviendo.", "Tostá el pan y serví."], "stepMeta": [{"tip": "Batí solo hasta integrar."}, {"minutes": 4, "tip": "Retirá del fuego cuando todavía estén húmedos."}], "symbol": "🍳", "color": "gold", "calories": 330, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/scrambled-eggs-toast.webp", "imageAlt": "Huevos revueltos cremosos con tostadas integrales"}, {"id": "overnight-oats", "name": "Avena nocturna con manzana", "description": "Avena fresca preparada con anticipación.", "category": "Desayuno", "minutes": 10, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Avena", "quantity": 60, "unit": "g"}, {"name": "Leche", "quantity": 180, "unit": "ml"}, {"name": "Manzana", "quantity": 1, "unit": "u"}], "steps": ["Mezclá la avena con la leche.", "Refrigerá la preparación.", "Sumá la manzana antes de servir."], "stepMeta": [{"tip": "Usá un recipiente con tapa."}, {"minutes": 480, "tip": "Dejala reposar durante la noche."}], "symbol": "🥣", "color": "blue", "calories": 350, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/overnight-oats.webp", "imageAlt": "Avena nocturna con leche y manzana servida en un frasco de vidrio"}, {"id": "caprese-sandwich", "name": "Sándwich caprese", "description": "Pan tostado con tomate, queso y hojas frescas.", "category": "Almuerzo", "minutes": 15, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pan integral", "quantity": 2, "unit": "u"}, {"name": "Tomate", "quantity": 1, "unit": "u"}, {"name": "Queso", "quantity": 80, "unit": "g"}, {"name": "Hojas verdes", "quantity": 30, "unit": "g"}], "steps": ["Cortá el tomate y el queso.", "Armá el sándwich con las hojas.", "Tostalo hasta fundir el queso."], "stepMeta": [{"tip": "Secá el tomate para que el pan conserve su textura."}, {"minutes": 5}], "symbol": "🥪", "color": "green", "calories": 420, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/caprese-sandwich.webp", "imageAlt": "Sándwich caprese tostado con tomate, queso y hojas verdes"}, {"id": "tuna-rice-salad", "name": "Ensalada de arroz y atún", "description": "Almuerzo fresco con arroz, atún y vegetales.", "category": "Almuerzo", "minutes": 25, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Arroz", "quantity": 160, "unit": "g"}, {"name": "Atún", "quantity": 160, "unit": "g"}, {"name": "Tomate", "quantity": 1, "unit": "u"}, {"name": "Aceite de oliva", "quantity": 20, "unit": "ml"}], "steps": ["Cociná el arroz.", "Escurrí el atún y cortá el tomate.", "Mezclá todo con aceite."], "stepMeta": [{"minutes": 15, "tip": "Enfriá el arroz extendido para que quede suelto."}], "symbol": "🐟", "color": "blue", "calories": 480, "dietaryTags": ["Sin TACC", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/tuna-rice-salad.webp", "imageAlt": "Ensalada de arroz con atún y tomate servida en un bol"}, {"id": "vegetable-wrap", "name": "Wrap de verduras y hummus", "description": "Wrap liviano con verduras crocantes.", "category": "Almuerzo", "minutes": 18, "portions": 2, "difficulty": "Fácil", "ingredients": [{"name": "Tortillas", "quantity": 2, "unit": "u"}, {"name": "Garbanzos", "quantity": 180, "unit": "g"}, {"name": "Zanahoria", "quantity": 1, "unit": "u"}, {"name": "Hojas verdes", "quantity": 60, "unit": "g"}], "steps": ["Procesá los garbanzos hasta formar un hummus.", "Cortá la zanahoria y lavá las hojas.", "Rellená y enrollá las tortillas."], "stepMeta": [{"minutes": 5, "tip": "Agregá agua de a cucharadas para ajustar el hummus."}, {"tip": "Doblá los extremos antes de enrollar."}], "symbol": "🌯", "color": "pink", "calories": 390, "dietaryTags": ["Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "image": "/assets/recipes/vegetable-wrap.webp", "imageAlt": "Wrap cortado con hummus, zanahoria y hojas verdes"}, {"id": "tomato-risotto", "name": "Risotto de tomate", "description": "Arroz cremoso con tomate y queso.", "category": "Cena", "minutes": 38, "portions": 3, "difficulty": "Intermedia", "ingredients": [{"name": "Arroz", "quantity": 240, "unit": "g"}, {"name": "Tomate", "quantity": 3, "unit": "u"}, {"name": "Queso rallado", "quantity": 60, "unit": "g"}], "steps": ["Cociná el tomate hasta obtener una salsa.", "Agregá el arroz y líquido de a poco.", "Terminá con queso rallado."], "stepMeta": [{"minutes": 10, "tip": "Cociná el tomate hasta concentrar su sabor."}, {"minutes": 20, "tip": "Revolvé con frecuencia para liberar el almidón."}], "symbol": "🍚", "color": "pink", "calories": 510, "dietaryTags": ["Sin TACC", "Vegetariana", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/tomato-risotto.webp", "imageAlt": "Risotto cremoso de tomate con queso rallado"}, {"id": "baked-fish-potatoes", "name": "Pescado al horno con papas", "description": "Cena completa de pescado, papas y limón.", "category": "Cena", "minutes": 45, "portions": 2, "difficulty": "Intermedia", "ingredients": [{"name": "Filet de pescado", "quantity": 400, "unit": "g"}, {"name": "Papa", "quantity": 500, "unit": "g"}, {"name": "Limón", "quantity": 1, "unit": "u"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}], "steps": ["Cortá y condimentá las papas.", "Horneá las papas hasta que empiecen a dorar.", "Sumá el pescado y cociná hasta que esté tierno."], "stepMeta": [{"durationMinutes": 8, "stepIngredients": [{"name": "Papa", "quantity": 500, "unit": "g"}, {"name": "Aceite de oliva", "quantity": 30, "unit": "ml"}], "utensils": ["Tabla", "Cuchillo", "Fuente para horno"], "tip": "Cortá las papas del mismo grosor."}, {"durationMinutes": 25, "utensils": ["Horno", "Fuente para horno"], "temperature": "200 °C", "warning": "Usá guantes térmicos al mover la fuente."}, {"durationMinutes": 15, "stepIngredients": [{"name": "Filet de pescado", "quantity": 400, "unit": "g"}, {"name": "Limón", "quantity": 1, "unit": "u"}], "utensils": ["Fuente para horno", "Tenedor"], "temperature": "200 °C", "tip": "El pescado debe separarse fácilmente con un tenedor."}], "symbol": "🐟", "color": "blue", "calories": 530, "dietaryTags": ["Sin TACC", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/baked-fish-potatoes.webp", "imageAlt": "Filet de pescado al horno con papas doradas y limón"}, {"id": "spinach-pie", "name": "Tarta de espinaca", "description": "Tarta casera de espinaca, huevo y queso.", "category": "Cena", "minutes": 55, "portions": 4, "difficulty": "Intermedia", "ingredients": [{"name": "Espinaca", "quantity": 400, "unit": "g"}, {"name": "Huevos", "quantity": 3, "unit": "u"}, {"name": "Queso", "quantity": 150, "unit": "g"}, {"name": "Masa para tarta", "quantity": 1, "unit": "u"}], "steps": ["Salteá y escurrí la espinaca.", "Mezclá con huevos y queso.", "Rellená la masa y horneá."], "stepMeta": [{"minutes": 8, "tip": "Escurrí muy bien la espinaca."}, {"tip": "Probá el relleno antes de sumar los huevos."}, {"minutes": 35}], "symbol": "🥧", "color": "green", "calories": 460, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/spinach-pie.webp", "imageAlt": "Porción de tarta casera de espinaca, huevo y queso"}, {"id": "pear-yogurt-cup", "name": "Copa de pera y yogur", "description": "Merienda fresca con fruta y avena tostada.", "category": "Merienda", "minutes": 10, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Pera", "quantity": 1, "unit": "u"}, {"name": "Yogur", "quantity": 180, "unit": "g"}, {"name": "Avena", "quantity": 30, "unit": "g"}], "steps": ["Cortá la pera.", "Alterná capas de yogur y fruta.", "Terminá con avena."], "stepMeta": [{"tip": "Conservá la cáscara si está firme y bien lavada."}], "symbol": "🍐", "color": "green", "calories": 270, "dietaryTags": ["Sin TACC", "Vegetariana", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/pear-yogurt-cup.webp", "imageAlt": "Copa de yogur con pera y avena tostada"}, {"id": "cheese-scones", "name": "Scones de queso", "description": "Bocados tibios para acompañar la merienda.", "category": "Merienda", "minutes": 32, "portions": 6, "difficulty": "Intermedia", "ingredients": [{"name": "Harina", "quantity": 250, "unit": "g"}, {"name": "Queso rallado", "quantity": 100, "unit": "g"}, {"name": "Leche", "quantity": 120, "unit": "ml"}], "steps": ["Mezclá harina y queso.", "Agregá leche hasta unir.", "Cortá los scones y horneá."], "stepMeta": [{"tip": "No amases de más."}, {"tip": "La masa debe quedar apenas unida."}, {"minutes": 18}], "symbol": "🧀", "color": "gold", "calories": 240, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/cheese-scones.webp", "imageAlt": "Scones de queso recién horneados servidos en un plato"}, {"id": "banana-smoothie", "name": "Licuado de banana y avena", "description": "Merienda cremosa lista en pocos minutos.", "category": "Merienda", "minutes": 6, "portions": 1, "difficulty": "Fácil", "ingredients": [{"name": "Banana", "quantity": 1, "unit": "u"}, {"name": "Leche", "quantity": 250, "unit": "ml"}, {"name": "Avena", "quantity": 25, "unit": "g"}], "steps": ["Colocá todos los ingredientes en la licuadora.", "Procesá hasta obtener una textura lisa."], "stepMeta": [{"tip": "Usá banana fría para un resultado más fresco."}, {"minutes": 2}], "symbol": "🥤", "color": "pink", "calories": 320, "dietaryTags": ["Vegetariana", "Sin frutos secos"], "image": "/assets/recipes/banana-smoothie.webp", "imageAlt": "Licuado cremoso de banana y avena servido en un vaso"}, {"id": "roasted-vegetable-soup", "name": "Sopa de verduras asadas", "description": "Sopa suave de calabaza, zanahoria y tomate.", "category": "Cena", "minutes": 50, "portions": 4, "difficulty": "Fácil", "ingredients": [{"name": "Calabaza", "quantity": 500, "unit": "g"}, {"name": "Zanahoria", "quantity": 2, "unit": "u"}, {"name": "Tomate", "quantity": 2, "unit": "u"}, {"name": "Aceite de oliva", "quantity": 25, "unit": "ml"}], "steps": ["Cortá y condimentá las verduras.", "Asalas hasta que estén tiernas.", "Procesá con agua caliente hasta lograr la textura deseada."], "stepMeta": [{"tip": "Cortá piezas similares para una cocción pareja."}, {"minutes": 35}, {"tip": "Agregá el líquido gradualmente."}], "symbol": "🥣", "color": "gold", "calories": 220, "featured": true, "dietaryTags": ["Sin TACC", "Vegana", "Vegetariana", "Sin lactosa", "Sin frutos secos"], "crossContaminationNote": "Aunque los ingredientes no contienen gluten, verificá rótulos y evitá la contaminación cruzada en superficies y utensilios compartidos.", "image": "/assets/recipes/roasted-vegetable-soup.webp", "imageAlt": "Sopa de calabaza, zanahoria y tomate asados en un cuenco"}]$seed$::jsonb) x;
-- Remote objects override seed objects exactly as mergeRecipeSeed does.
insert into cocinapp_rehearsal.src_recipes select x->>'id', x, 'remote'
from public.shared_recipes r cross join lateral jsonb_array_elements(r.recipes) x where catalog_key='main'
on conflict(legacy_id) do update set body=excluded.body, origin=excluded.origin;

insert into public.categories(id,legacy_id,name,normalized_name,active,is_deleted)
select cocinapp_rehearsal.key_id('category',x->>'id'),x->>'id',x->>'name',cocinapp_rehearsal.norm(x->>'name'),
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'categories') x;
-- Roots first, then derived units; the trigger requires a root of the same dimension.
insert into public.units(id,legacy_id,name,abbreviation,dimension,active,is_deleted)
select cocinapp_rehearsal.key_id('unit',x->>'id'),x->>'id',x->>'name',x->>'abbreviation',
  case x->>'dimension' when 'masa' then 'mass' when 'volumen' then 'volume' when 'conteo' then 'count' else x->>'dimension' end,
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'units') x
where nullif(x->>'baseUnitId','') is null;
insert into public.units(id,legacy_id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted)
select cocinapp_rehearsal.key_id('unit',x->>'id'),x->>'id',x->>'name',x->>'abbreviation',
  case x->>'dimension' when 'masa' then 'mass' when 'volumen' then 'volume' when 'conteo' then 'count' else x->>'dimension' end,
  cocinapp_rehearsal.key_id('unit',x->>'baseUnitId'),(x->>'equivalenceMultiplier')::numeric,
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'units') x
where nullif(x->>'baseUnitId','') is not null;
insert into public.ingredients(id,legacy_id,name,normalized_name,category_id,base_unit_id,active,is_deleted)
select cocinapp_rehearsal.key_id('ingredient',x->>'id'),x->>'id',x->>'name',cocinapp_rehearsal.norm(x->>'name'),
  cocinapp_rehearsal.key_id('category',x->>'categoryId'),cocinapp_rehearsal.key_id('unit',x->>'baseUnitId'),
  (x->>'active')::boolean,(x->>'isDeleted')::boolean
from cocinapp_rehearsal.src_core cross join lateral jsonb_array_elements(payload->'ingredients') x;

create table cocinapp_rehearsal.src_ingredients as
select r.legacy_id, n::integer as position, x,
  case when r.origin='remote' then (select id from public.ingredients where legacy_id=x->>'ingredientId')
    else (select id from public.ingredients where normalized_name=cocinapp_rehearsal.norm(x->>'name')) end as ingredient_id,
  case when r.origin='remote' then (select id from public.units where legacy_id=x->>'unitId')
    else (select id from public.units where abbreviation=x->>'unit') end as unit_id
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'ingredients') with ordinality a(x,n);
-- This public-catalog report identifies mappings requiring review; never invent them.
select legacy_id as recipe_legacy_id, x->>'name' as seed_ingredient_name,
  case when ingredient_id is null then 'missing ingredient' else 'missing unit' end as blocker
from cocinapp_rehearsal.src_ingredients where ingredient_id is null or unit_id is null;
do $$ begin
  if exists(select 1 from cocinapp_rehearsal.src_ingredients where ingredient_id is null or unit_id is null) then
    raise exception 'Hay ingredientes o unidades sin asociación. Revisar el reporte; el ensayo se revierte.';
  end if;
end $$;

insert into public.recipes(id,legacy_id,recipe_source,title,author,description,category_label,total_minutes,
  preparation_minutes,cooking_minutes,portions,difficulty,calories_per_portion,publication_status,
  active,is_deleted,featured,symbol,color,cross_contamination_note,image_path,image_alt,created_at,updated_at)
select cocinapp_rehearsal.key_id('recipe',legacy_id),legacy_id,'official',coalesce(body->>'title',body->>'name'),
  coalesce(body->>'author','CocinAPP'),coalesce(body->>'description',''),coalesce(body->>'category',''),
  (body->>'minutes')::integer,(body->>'preparationMinutes')::integer,(body->>'cookingMinutes')::integer,
  (body->>'portions')::integer,
  case body->>'difficulty' when 'Fácil' then 'easy' when 'Intermedia' then 'intermediate' when 'Avanzada' then 'advanced' else body->>'difficulty' end,
  (body->>'calories')::numeric,coalesce(body->>'status','published'),coalesce((body->>'active')::boolean,true),
  coalesce((body->>'isDeleted')::boolean,false),coalesce((body->>'featured')::boolean,false),
  coalesce(body->>'symbol',''),coalesce(body->>'color','green'),body->>'crossContaminationNote',body->>'image',body->>'imageAlt',
  coalesce((body->>'createdAt')::timestamptz,transaction_timestamp()),coalesce((body->>'updatedAt')::timestamptz,transaction_timestamp())
from cocinapp_rehearsal.src_recipes;
insert into public.recipe_ingredients(id,recipe_id,ingredient_id,quantity,unit_id,note,position)
select cocinapp_rehearsal.key_id('recipe-ingredient',legacy_id||':'||position),cocinapp_rehearsal.key_id('recipe',legacy_id),
  ingredient_id,(x->>'quantity')::numeric,unit_id,coalesce(x->>'note',''),position from cocinapp_rehearsal.src_ingredients;
insert into public.recipe_steps(id,recipe_id,position,instruction,duration_minutes,temperature,tip,warning,utensils,special_instructions)
select cocinapp_rehearsal.key_id('recipe-step',legacy_id||':'||n),cocinapp_rehearsal.key_id('recipe',legacy_id),n::integer,x #>> '{}',
  coalesce((m->>'durationMinutes')::integer,(m->>'minutes')::integer),m->>'temperature',m->>'tip',m->>'warning',
  coalesce(array(select jsonb_array_elements_text(m->'utensils')),'{}'),m->>'specialInstructions'
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements(body->'steps') with ordinality a(x,n)
cross join lateral (select body->'stepMeta'->(n::integer-1) as m) metadata;
insert into public.recipe_meal_shifts(recipe_id,meal_shift)
select distinct cocinapp_rehearsal.key_id('recipe',legacy_id),case x when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch' when 'Merienda' then 'snack' when 'Cena' then 'dinner' else x end
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements_text(coalesce(body->'mealShifts',jsonb_build_array(coalesce(body->>'mealShift',body->>'category')))) x;

insert into public.dietary_tags(tag_key,label) values
 ('gluten-free','Sin TACC'),('vegetarian','Vegetariana'),('vegan','Vegana'),('lactose-free','Sin lactosa'),('nut-free','Sin frutos secos');
create table cocinapp_rehearsal.src_tags as
select legacy_id,x as label,case cocinapp_rehearsal.norm(x) when 'sin tacc' then 'gluten-free'
 when 'vegetariana' then 'vegetarian' when 'vegetariano' then 'vegetarian'
 when 'vegana' then 'vegan' when 'vegano' then 'vegan' when 'sin lactosa' then 'lactose-free'
 when 'sin frutos secos' then 'nut-free' else 'label-'||md5(x) end as tag_key
from cocinapp_rehearsal.src_recipes cross join lateral jsonb_array_elements_text(body->'dietaryTags') x;
insert into public.dietary_tags(tag_key,label) select distinct tag_key,label from cocinapp_rehearsal.src_tags
on conflict(tag_key) do nothing;
insert into public.recipe_dietary_tags(recipe_id,dietary_tag_id)
select distinct cocinapp_rehearsal.key_id('recipe',s.legacy_id),t.id from cocinapp_rehearsal.src_tags s join public.dietary_tags t using(tag_key);

-- Link per-step metadata to ingredients without dropping unresolvable links.
create table cocinapp_rehearsal.src_step_links as
select r.legacy_id, n::integer as step_position, value as old_ingredient_id
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'stepMeta') with ordinality a(m,n)
cross join lateral jsonb_array_elements_text(m->'ingredientIds') value;
do $$ begin
 if exists(select 1 from cocinapp_rehearsal.src_step_links s where not exists(select 1 from cocinapp_rehearsal.src_ingredients i
   join public.ingredients g on g.id=i.ingredient_id where i.legacy_id=s.legacy_id and g.legacy_id=s.old_ingredient_id)) then
   raise exception 'Metadatos de pasos con ingredientes sin resolver.';
 end if;
end $$;
insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id)
select distinct cocinapp_rehearsal.key_id('recipe-step',s.legacy_id||':'||s.step_position),
 cocinapp_rehearsal.key_id('recipe-ingredient',i.legacy_id||':'||i.position)
from cocinapp_rehearsal.src_step_links s join cocinapp_rehearsal.src_ingredients i on i.legacy_id=s.legacy_id
join public.ingredients g on g.id=i.ingredient_id and g.legacy_id=s.old_ingredient_id;

-- Seed step metadata uses named ingredients rather than legacy ingredient IDs.
create table cocinapp_rehearsal.src_seed_steps as
select r.legacy_id,n::integer as step_position,item
from cocinapp_rehearsal.src_recipes r cross join lateral jsonb_array_elements(body->'stepMeta') with ordinality a(m,n)
cross join lateral jsonb_array_elements(m->'stepIngredients') item where origin='seed';
do $$ begin
 if exists(select 1 from cocinapp_rehearsal.src_seed_steps s where (select count(*) from public.recipe_ingredients ri
   join public.ingredients i on i.id=ri.ingredient_id join public.units u on u.id=ri.unit_id
   where ri.recipe_id=cocinapp_rehearsal.key_id('recipe',s.legacy_id)
   and i.normalized_name=cocinapp_rehearsal.norm(s.item->>'name') and u.abbreviation=s.item->>'unit') <> 1) then
   raise exception 'Ingredientes por paso del catálogo incluido sin asociación inequívoca.';
 end if;
end $$;
insert into public.recipe_step_ingredients(step_id,recipe_ingredient_id,quantity_override)
select cocinapp_rehearsal.key_id('recipe-step',s.legacy_id||':'||s.step_position),ri.id,(s.item->>'quantity')::numeric
from cocinapp_rehearsal.src_seed_steps s join public.recipe_ingredients ri on ri.recipe_id=cocinapp_rehearsal.key_id('recipe',s.legacy_id)
join public.ingredients i on i.id=ri.ingredient_id and i.normalized_name=cocinapp_rehearsal.norm(s.item->>'name')
join public.units u on u.id=ri.unit_id and u.abbreviation=s.item->>'unit';


-- Explicit staging RLS avoids SQL Editor appending ALTERs after ROLLBACK.
alter table cocinapp_rehearsal.src_core enable row level security;
alter table cocinapp_rehearsal.src_recipes enable row level security;
alter table cocinapp_rehearsal.src_ingredients enable row level security;
alter table cocinapp_rehearsal.src_tags enable row level security;
alter table cocinapp_rehearsal.src_step_links enable row level security;
alter table cocinapp_rehearsal.src_seed_steps enable row level security;

select 'categories' as dataset,count(*) as converted from public.categories
union all select 'units',count(*) from public.units
union all select 'ingredients',count(*) from public.ingredients
union all select 'recipes',count(*) from public.recipes
union all select 'recipe_ingredients',count(*) from public.recipe_ingredients
union all select 'recipe_steps',count(*) from public.recipe_steps;
-- REHEARSAL ONLY. Requires the relational schema and merged recipe backfill.
-- Run on an isolated copy as the database operator; never as an application user.
-- No legacy rows or pantry quantities are modified. All inserts roll back.

set local timezone = 'UTC';
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- A consistent source snapshot is required for reconciliation.
lock table public.personal_data in share mode;
lock table public.recipes in share mode;

do $$
declare row_data record; item jsonb; p jsonb; target_recipe uuid; event_id uuid;
  session_id uuid; target_plan uuid; meal_date date; week_start date;
  meal_shift text; cooked_at timestamptz; started_at timestamptz;
  expected_count bigint; actual_count bigint;
begin
  if exists(select 1 from public.profiles)
    or exists(select 1 from public.user_dietary_preferences)
    or exists(select 1 from public.favorite_recipes)
    or exists(select 1 from public.meal_plans)
    or exists(select 1 from public.meal_plan_slots)
    or exists(select 1 from public.shopping_lists)
    or exists(select 1 from public.cooking_sessions)
    or exists(select 1 from public.cooking_events) then
    raise exception 'Destino personal no vacío: se rechaza sobrescribir registros.';
  end if;
  if exists(select 1 from public.personal_data where
    (data_key = 'profile' and jsonb_typeof(value) <> 'object')
    or (data_key <> 'profile' and jsonb_typeof(value) <> 'array')) then
    raise exception 'Formato de documento personal no soportado.';
  end if;
  if exists(select 1 from public.personal_data
    where data_key in ('cooking_progress','shopping') and jsonb_array_length(value) > 0) then
    raise exception 'Hay compras o sesiones activas nuevas: requieren su conversor antes de continuar.';
  end if;
  if exists(select 1 from public.personal_data d
    where not exists(select 1 from auth.users u where u.id = d.user_id)) then
    raise exception 'Documento personal sin cuenta Auth correspondiente.';
  end if;

  -- Stable canonical tag keys. Existing tag rows remain authoritative.
  insert into public.dietary_tags(id, tag_key, label)
  select md5('cocinapp:dietary:' || key)::uuid, key, label
  from (values ('gluten-free','Sin TACC'),('vegetarian','Vegetariana'),
    ('vegan','Vegana'),('lactose-free','Sin lactosa'),('nut-free','Sin frutos secos')) v(key,label)
  on conflict (tag_key) do nothing;

  for row_data in select user_id, value, updated_at from public.personal_data where data_key='profile' loop
    p := row_data.value;
    if jsonb_typeof(p -> 'name') is distinct from 'string'
      or length(trim(p ->> 'name')) not between 1 and 120 then
      raise exception 'Perfil sin nombre válido.';
    end if;
    if exists(select 1 from jsonb_object_keys(p) key where key not in
      ('name','email','birthDate','weightKg','heightCm','metabolicSex','activityLevel','goal','preferences')) then
      raise exception 'Perfil con campos no contemplados por el conversor.';
    end if;
    if (p ? 'weightKg' and jsonb_typeof(p -> 'weightKg') <> 'number')
      or (p ? 'heightCm' and jsonb_typeof(p -> 'heightCm') <> 'number')
      or (p ? 'preferences' and jsonb_typeof(p -> 'preferences') <> 'array') then
      raise exception 'Tipos de campos de perfil incompatibles.';
    end if;
    insert into public.profiles(user_id,display_name,birth_date,weight_kg,height_cm,
      metabolic_sex,activity_level,goal,created_at,updated_at)
    values(row_data.user_id,p ->> 'name',nullif(p ->> 'birthDate','')::date,
      (p ->> 'weightKg')::numeric,(p ->> 'heightCm')::numeric,p ->> 'metabolicSex',
      p ->> 'activityLevel',p ->> 'goal',row_data.updated_at,row_data.updated_at);
    -- Email stays in Auth; no second email source is introduced.
    for item in select value from jsonb_array_elements(coalesce(p -> 'preferences','[]'::jsonb)) loop
      if jsonb_typeof(item) <> 'string' or not exists(select 1 from public.dietary_tags where tag_key=item #>> '{}') then
        raise exception 'Preferencia dietética no reconocida.';
      end if;
      insert into public.user_dietary_preferences(user_id,dietary_tag_id,created_at)
      select row_data.user_id,id,row_data.updated_at from public.dietary_tags where tag_key=item #>> '{}'
      on conflict (user_id,dietary_tag_id) do nothing;
    end loop;
  end loop;

  for row_data in select user_id,value,updated_at from public.personal_data where data_key='favorites' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'string' then raise exception 'Favorito con identificador inválido.'; end if;
      select id into target_recipe from public.recipes where legacy_id=item #>> '{}';
      if target_recipe is null then raise exception 'Favorito sin receta migrada.'; end if;
      insert into public.favorite_recipes(user_id,recipe_id,created_at)
      values(row_data.user_id,target_recipe,row_data.updated_at);
    end loop;
  end loop;

  for row_data in select user_id,value,updated_at from public.personal_data where data_key='meal_plan' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'object'
        or jsonb_typeof(item -> 'recipeId') is distinct from 'string'
        or jsonb_typeof(item -> 'portions') is distinct from 'number' then
        raise exception 'Asignación del plan con formato inválido.';
      end if;
      meal_date := (item ->> 'date')::date;
      week_start := meal_date - (extract(isodow from meal_date)::integer - 1);
      meal_shift := case item ->> 'meal' when 'Desayuno' then 'breakfast' when 'Almuerzo' then 'lunch'
        when 'Merienda' then 'snack' when 'Cena' then 'dinner' end;
      if meal_date is null or meal_shift is null
        or (item ->> 'portions')::numeric <> trunc((item ->> 'portions')::numeric) then
        raise exception 'Fecha, turno o porciones del plan inválidos.';
      end if;
      target_plan := md5('cocinapp:plan:' || row_data.user_id::text || ':' || week_start::text)::uuid;
      insert into public.meal_plans(id,owner_user_id,week_start,created_at,updated_at)
      values(target_plan,row_data.user_id,week_start,row_data.updated_at,row_data.updated_at)
      on conflict on constraint meal_plans_owner_user_id_week_start_key do nothing;
      select id into target_recipe from public.recipes where legacy_id=item ->> 'recipeId';
      if target_recipe is null then raise exception 'Plan sin receta migrada.'; end if;
      insert into public.meal_plan_slots(id,plan_id,meal_date,meal_shift,recipe_id,portions,created_at)
      values(md5('cocinapp:slot:' || row_data.user_id::text || ':' || meal_date::text || ':' || meal_shift)::uuid,
        target_plan,meal_date,meal_shift,target_recipe,(item ->> 'portions')::integer,row_data.updated_at);
    end loop;
  end loop;

  -- Each legacy history event has its own closed synthetic session. The recipe
  -- snapshot reflects the catalog available during migration, not an invented
  -- historical recipe version. No consumption/stock deductions are fabricated.
  for row_data in select user_id,value,updated_at from public.personal_data where data_key='cooking_history' loop
    for item in select value from jsonb_array_elements(row_data.value) loop
      if jsonb_typeof(item) <> 'object' or nullif(item ->> 'id','') is null
        or jsonb_typeof(item -> 'portions') is distinct from 'number'
        or (item ->> 'portions')::numeric <> trunc((item ->> 'portions')::numeric) then
        raise exception 'Evento de cocina con formato inválido.';
      end if;
      select id into target_recipe from public.recipes where legacy_id=item ->> 'recipeId';
      if target_recipe is null then raise exception 'Historial sin receta migrada.'; end if;
      cooked_at := (item ->> 'cookedAt')::timestamptz;
      started_at := coalesce((item ->> 'sessionStartedAt')::timestamptz,cooked_at);
      if cooked_at is null or started_at > cooked_at then raise exception 'Fechas del historial inválidas.'; end if;
      event_id := md5('cocinapp:history:' || row_data.user_id::text || ':' || (item ->> 'id'))::uuid;
      session_id := md5('cocinapp:history-session:' || row_data.user_id::text || ':' || (item ->> 'id'))::uuid;
      select jsonb_build_object('legacyRecipeId',r.legacy_id,'title',r.title,
        'snapshotOrigin','migration_catalog','legacyEvent',item,
        'ingredients',(select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.recipe_ingredients i where i.recipe_id=r.id),
        'steps',(select coalesce(jsonb_agg(to_jsonb(s) order by s.position),'[]'::jsonb) from public.recipe_steps s where s.recipe_id=r.id))
        into p from public.recipes r where r.id=target_recipe;
      insert into public.cooking_sessions(id,owner_user_id,recipe_id,recipe_snapshot,portions,
        client_idempotency_key,started_at,finished_at)
      values(session_id,row_data.user_id,target_recipe,p,(item ->> 'portions')::integer,
        session_id,started_at,cooked_at);
      insert into public.cooking_events(id,owner_user_id,session_id,recipe_id,recipe_snapshot,portions,cooked_at)
      values(event_id,row_data.user_id,session_id,target_recipe,p,(item ->> 'portions')::integer,cooked_at);
    end loop;
  end loop;

  -- Empty legacy shopping documents become empty active lists; their rows remain
  -- untouched. Non-empty lists/progress were rejected before inserting anything.
  insert into public.shopping_lists(id,owner_user_id,created_at,updated_at)
  select md5('cocinapp:shopping:' || user_id::text)::uuid,user_id,updated_at,updated_at
  from public.personal_data where data_key='shopping';

  select count(*) into expected_count from public.personal_data where data_key='profile';
  select count(*) into actual_count from public.profiles;
  if expected_count <> actual_count then raise exception 'Reconciliación de perfiles fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='favorites';
  select count(*) into actual_count from public.favorite_recipes;
  if expected_count <> actual_count then raise exception 'Reconciliación de favoritos fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='meal_plan';
  select count(*) into actual_count from public.meal_plan_slots;
  if expected_count <> actual_count then raise exception 'Reconciliación del plan fallida.'; end if;
  select coalesce(sum(jsonb_array_length(value)),0) into expected_count from public.personal_data where data_key='cooking_history';
  select count(*) into actual_count from public.cooking_events;
  if expected_count <> actual_count then raise exception 'Reconciliación del historial fallida.'; end if;
exception when others then
  -- Do not include SQLERRM/DETAIL: database cast errors can contain private values.
  raise exception 'Conversión personal cancelada; datos inválidos, destino ocupado o referencias no migradas. SQLSTATE %.',sqlstate;
end;
$$;

select 'profiles' as dataset,count(*) as converted from public.profiles
union all select 'preferences',count(*) from public.user_dietary_preferences
union all select 'favorites',count(*) from public.favorite_recipes
union all select 'plan_slots',count(*) from public.meal_plan_slots
union all select 'cooking_history',count(*) from public.cooking_events
union all select 'empty_active_shopping_lists',count(*) from public.shopping_lists;

-- REHEARSAL ONLY. Run in an isolated copy after the catalog rehearsal stage.

set local lock_timeout = '5s';
lock table public.pantry_items in share row exclusive mode;
do $$ begin
  if exists(select 1 from public.pantry_items where ingredient_ref is not null or unit_ref is not null) then
    raise exception 'La despensa ya tiene referencias relacionales; se rechaza sobrescribirlas.';
  end if;
end $$;
-- An explicit legacy ID is authoritative; only rows without one use exact
-- normalized names. Never use approximate matching or alter inventory values.
update public.pantry_items p set ingredient_ref=i.id
from public.ingredients i
where (p.ingredient_id is not null and i.legacy_id=p.ingredient_id)
  or (p.ingredient_id is null and i.normalized_name=
    lower(translate(regexp_replace(trim(p.name),'\s+',' ','g'),'áéíóúüñÁÉÍÓÚÜÑ','aeiouunAEIOUUN')));
update public.pantry_items p set unit_ref=u.id
from public.units u where u.abbreviation=p.unit;
select 'pantry_rows' as dataset,count(*) as total from public.pantry_items
union all select 'ingredient_unmatched',count(*) from public.pantry_items where ingredient_ref is null
union all select 'unit_unmatched',count(*) from public.pantry_items where unit_ref is null
union all select 'dimension_mismatch',count(*) from public.pantry_items p
join public.ingredients i on i.id=p.ingredient_ref join public.units b on b.id=i.base_unit_id
join public.units u on u.id=p.unit_ref where b.dimension<>u.dimension;
-- One result table: SQL Editor shows only the last non-empty result set.
select 'catalog' as section, 'categories' as dataset, count(*) as total from public.categories
union all select 'catalog','units',count(*) from public.units
union all select 'catalog','ingredients',count(*) from public.ingredients
union all select 'catalog','recipes',count(*) from public.recipes
union all select 'catalog','recipe_ingredients',count(*) from public.recipe_ingredients
union all select 'catalog','recipe_steps',count(*) from public.recipe_steps
union all select 'personal','profiles',count(*) from public.profiles
union all select 'personal','preferences',count(*) from public.user_dietary_preferences
union all select 'personal','favorites',count(*) from public.favorite_recipes
union all select 'personal','plan_slots',count(*) from public.meal_plan_slots
union all select 'personal','cooking_history',count(*) from public.cooking_events
union all select 'personal','empty_active_shopping_lists',count(*) from public.shopping_lists
union all select 'security','domain_tables_with_rls',count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity and c.relname in ('dietary_tags','nutrition_config','profiles','user_dietary_preferences','categories','units','ingredients','ingredient_dietary_tags','recipes','recipe_meal_shifts','recipe_dietary_tags','recipe_ingredients','recipe_steps','recipe_step_ingredients','favorite_recipes','meal_plans','meal_plan_slots','pantry_receipts','shopping_lists','shopping_items','shopping_item_sources','pantry_receipt_items','cooking_sessions','cooking_session_steps','cooking_events','cooking_event_ingredients','recipe_generation_requests','receipt_recognition_requests')
union all select 'pantry','rows',count(*) from public.pantry_items
union all select 'pantry','ingredient_unmatched',count(*) from public.pantry_items where ingredient_ref is null
union all select 'pantry','unmatched_explicit_id',count(*) from public.pantry_items where ingredient_ref is null and ingredient_id is not null
union all select 'pantry','unmatched_name',count(*) from public.pantry_items where ingredient_ref is null and ingredient_id is null
union all select 'pantry','unit_unmatched',count(*) from public.pantry_items where unit_ref is null
union all select 'pantry','dimension_mismatch',count(*) from public.pantry_items p join public.ingredients i on i.id=p.ingredient_ref join public.units b on b.id=i.base_unit_id join public.units u on u.id=p.unit_ref where b.dimension<>u.dimension;
rollback;
